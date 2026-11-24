import { createClient } from "npm:@supabase/supabase-js@2.50.0";
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "npm:jose@5.9.6";

const appleIssuer = "https://appleid.apple.com";
const appleKeys = createRemoteJWKSet(new URL("/auth/keys", appleIssuer));
class InvalidAppleGrant extends Error {}

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

  const body = await request.json().catch(() => null);
  const authorizationCode = body?.authorization_code;
  const action = body?.action;
  if (action !== "status" && action !== "resume" &&
      (typeof authorizationCode !== "string" || !authorizationCode)) {
    return json({ error: "Apple authorization is required" }, 400);
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data, error: userError } = await userClient.auth.getUser();
  if (userError && (!userError.status || userError.status >= 500 || userError.status === 429)) {
    return json({ error: "Authentication service unavailable", code: "auth_unavailable" }, 503);
  }
  if (userError || !data.user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const expectedAppleSubject = data.user.identities?.find(
    (identity) => identity.provider === "apple",
  )?.identity_data?.sub;
  if (typeof expectedAppleSubject !== "string") {
    return json({ error: "Apple identity was not found" }, 409);
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const requests = adminClient.from("account_deletion_requests");
  const { data: checkpoint, error: readError } = await requests.select("user_id")
    .eq("user_id", data.user.id).maybeSingle();
  if (readError) return json({ error: "Deletion status unavailable", code: "status_unavailable" }, 503);
  if (action === "status") return json({ canResume: checkpoint !== null }, 200);
  if (!checkpoint && action === "resume") return json({ error: "Apple authorization is required" }, 409);

  if (action !== "resume") {
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
        return json({ error: "Apple identity does not match", code: "apple_identity_mismatch" }, 403);
      }

      await revokeAppleToken({
        refreshToken: appleTokens.refreshToken,
        clientID: appleClientID,
        clientSecret,
      });
    } catch (error) {
      if (error instanceof InvalidAppleGrant) {
        return json({ error: "A fresh Apple authorization code is required", code: "invalid_apple_grant" }, 400);
      }
      console.error(
        "Apple authorization revocation failed",
        error instanceof Error ? error.message : "Unknown error",
      );
      return json({ error: "Could not revoke Apple authorization", code: "apple_revocation_failed" }, 502);
    }
    const { error: checkpointError } = await requests.upsert({ user_id: data.user.id });
    if (checkpointError) return json({ error: "Could not record Apple revocation", code: "checkpoint_failed" }, 503);
  }

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    data.user.id,
  );
  if (deleteError) {
    console.error("delete-account failed", deleteError.message);
    return json({ error: "Could not delete account" }, 500);
  }

  return json({ deleted: true }, 200);
});

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
    .setAudience(appleIssuer)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(signingKey);
}

async function exchangeAppleAuthorizationCode(input: {
  authorizationCode: string;
  clientID: string;
  clientSecret: string;
}): Promise<{ refreshToken: string; subject: string }> {
  const response = await fetch(new URL("/auth/token", appleIssuer), {
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
  if (!response.ok && body.error === "invalid_grant") throw new InvalidAppleGrant();
  if (
    !response.ok ||
    typeof body.refresh_token !== "string" ||
    typeof body.id_token !== "string"
  ) {
    throw new Error(`Apple token exchange returned ${response.status}`);
  }

  const { payload } = await jwtVerify(body.id_token, appleKeys, {
    issuer: appleIssuer, audience: input.clientID, algorithms: ["RS256"], requiredClaims: ["exp", "sub"],
  });
  const subject = payload.sub;
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
  const response = await fetch(new URL("/auth/revoke", appleIssuer), {
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

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
