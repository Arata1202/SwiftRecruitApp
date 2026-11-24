import Foundation

/// Public website syntax only: no DNS lookup or changing TLD allowlist.
/// Requires a dotted DNS name (including IDN), not localhost or an IP literal.
enum WebURLNormalizer {
    static func normalizedString(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              !trimmed.contains("\\")
        else { return nil }

        // Only an anchored scheme counts; a query may itself contain https://.
        let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let candidate = hasScheme ? trimmed : "https://\(trimmed)"
        // Do not let Foundation repair malformed percent escapes.
        let bytes = Array(candidate.utf8)
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count,
                  isHex(bytes[index + 1]), isHex(bytes[index + 2]) else { return nil }
        }
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.user == nil, components.password == nil,
              let url = components.url,
              let host = url.host?.lowercased(),
              validPublicHost(host)
        else { return nil }
        if let port = components.port, !(1...65535).contains(port) { return nil }
        let authority = candidate.dropFirst(scheme.count + 3).prefix { !"/?#".contains($0) }
        guard !authority.hasSuffix(":"), !authority.contains("%") else { return nil }
        if let colon = authority.lastIndex(of: ":") {
            let digits = authority[authority.index(after: colon)...]
            guard digits.utf8.allSatisfy({ (48...57).contains($0) }), let port = UInt16(digits), port > 0 else { return nil }
        }
        components.scheme = scheme
        return components.url?.absoluteString
    }

    static func isValidOrEmpty(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || normalizedString(from: value) != nil
    }

    /// Invalid nonempty input must throw, never silently clear a stored URL.
    static func validatedString(from value: String, preservingUnchanged storedValue: String? = nil) throws -> String? {
        // Unrelated edits must not erase or force repair of a legacy URL.
        if let storedValue, value == storedValue { return storedValue }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let normalized = normalizedString(from: value),
              InputLimits.length(of: normalized) <= InputLimits.webURL else {
            throw ValidationError.invalidWebsite
        }
        return normalized
    }

    private static func validPublicHost(_ host: String) -> Bool {
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard name.utf8.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last,
              last.contains(where: { $0.isASCII && $0.isLetter }) else { return false }
        if last.hasPrefix("0x"), last.dropFirst(2).utf8.allSatisfy(isHex) { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63
                && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    enum ValidationError: LocalizedError {
        case invalidWebsite
        var errorDescription: String? { "有効な企業サイトURLを入力してください。" }
    }
}
