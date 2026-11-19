import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum NonceGenerator {
    static func random(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw AuthFlowError.nonceGenerationFailed(status)
            }

            for byte in bytes where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthFlowError: LocalizedError {
    case nonceGenerationFailed(OSStatus)
    case invalidCredential
    case missingIdentityToken
    case invalidIdentityToken

    var errorDescription: String? {
        switch self {
        case .nonceGenerationFailed:
            "ログインの準備ができませんでした。もう一度お試しください。"
        case .invalidCredential:
            "Appleのログイン情報を確認できませんでした。"
        case .missingIdentityToken, .invalidIdentityToken:
            "Appleから必要な認証情報を受け取れませんでした。"
        }
    }
}

