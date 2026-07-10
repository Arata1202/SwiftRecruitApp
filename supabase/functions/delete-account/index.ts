import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "Unauthorized" }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const appleTeamID = Deno.env.get("APPLE_TEAM_ID");
  const appleKeyID = Deno.env.get("APPLE_KEY_ID");
  const appleClientID = Deno.env.get("APPLE_CLIENT_ID");
  const applePrivateKey = Deno.env.get("APPLE_PRIVATE_KEY");

  if (
    !supabaseURL ||
    !publishableKey ||
    !serviceRoleKey ||
    !appleTeamID ||
    !appleKeyID ||
    !appleClientID ||
    !applePrivateKey
  ) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  const authorizationCode = await readAuthorizationCode(request);
  if (!authorizationCode) {
    return json({ error: "Apple authorization is required" }, 400);
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data, error: userError } = await userClient.auth.getUser();
  if (userError || !data.user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const expectedAppleSubject = data.user.identities?.find(
    (identity) => identity.provider === "apple",
  )?.identity_data?.sub;
  if (typeof expectedAppleSubject !== "string") {
    return json({ error: "Apple identity was not found" }, 409);
  }

  try {
    const clientSecret = await createAppleClientSecret({
      teamID: appleTeamID,
      keyID: appleKeyID,
      clientID: appleClientID,
      privateKey: applePrivateKey,
    });
    const appleTokens = await exchangeAppleAuthorizationCode({
      authorizationCode,
      clientID: appleClientID,
      clientSecret,
    });

    if (appleTokens.subject !== expectedAppleSubject) {
      return json({ error: "Apple identity does not match" }, 403);
    }

    await revokeAppleToken({
      refreshToken: appleTokens.refreshToken,
      clientID: appleClientID,
      clientSecret,
    });
  } catch (error) {
    console.error(
      "Apple authorization revocation failed",
      error instanceof Error ? error.message : "Unknown error",
    );
    return json({ error: "Could not revoke Apple authorization" }, 502);
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    data.user.id,
  );
  if (deleteError) {
    console.error("delete-account failed", deleteError.message);
    return json({ error: "Could not delete account" }, 500);
  }

  return json({ deleted: true }, 200);
});

async function readAuthorizationCode(request: Request): Promise<string | null> {
  try {
    const body = await request.json();
    const code = body?.authorization_code;
    return typeof code === "string" && code.length > 0 ? code : null;
  } catch {
    return null;
  }
}

async function createAppleClientSecret(input: {
  teamID: string;
  keyID: string;
  clientID: string;
  privateKey: string;
}): Promise<string> {
  const privateKey = input.privateKey.replaceAll("\\n", "\n");
  const signingKey = await importPKCS8(privateKey, "ES256");

  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: input.keyID })
    .setIssuer(input.teamID)
    .setSubject(input.clientID)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(signingKey);
}

async function exchangeAppleAuthorizationCode(input: {
  authorizationCode: string;
  clientID: string;
  clientSecret: string;
}): Promise<{ refreshToken: string; subject: string }> {
  const response = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code: input.authorizationCode,
      client_id: input.clientID,
      client_secret: input.clientSecret,
    }),
  });

  const body = await response.json();
  if (
    !response.ok ||
    typeof body.refresh_token !== "string" ||
    typeof body.id_token !== "string"
  ) {
    throw new Error(`Apple token exchange returned ${response.status}`);
  }

  const subject = decodeJWTPayload(body.id_token)?.sub;
  if (typeof subject !== "string") {
    throw new Error("Apple ID token did not contain a subject");
  }

  return { refreshToken: body.refresh_token, subject };
}

async function revokeAppleToken(input: {
  refreshToken: string;
  clientID: string;
  clientSecret: string;
}): Promise<void> {
  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      token: input.refreshToken,
      token_type_hint: "refresh_token",
      client_id: input.clientID,
      client_secret: input.clientSecret,
    }),
  });

  if (!response.ok) {
    throw new Error(`Apple token revocation returned ${response.status}`);
  }
}

function decodeJWTPayload(token: string): Record<string, unknown> | null {
  try {
    const payload = token.split(".")[1];
    if (!payload) return null;
    const normalized = payload.replaceAll("-", "+").replaceAll("_", "/");
    const padded = normalized.padEnd(
      normalized.length + ((4 - (normalized.length % 4)) % 4),
      "=",
    );
    return JSON.parse(atob(padded));
  } catch {
    return null;
  }
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
