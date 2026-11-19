import Foundation
import Supabase

enum UserFacingError {
    static func message(for error: Error, fallback: String) -> String {
        if error is RepositoryError || error is AuthFlowError || error is AccountDeletionError
            || error is WebURLNormalizer.ValidationError || error is NotificationTimingError {
            return error.localizedDescription
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "インターネット接続を確認してください。"
            case .timedOut:
                return "通信に時間がかかっています。しばらくしてからもう一度お試しください。"
            default:
                break
            }
        }

        return fallback
    }
}

enum AccountDeletionError: LocalizedError, Equatable {
    case operationInProgress
    case appleIdentityMismatch
    case rejected
    case resultUnknown

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            "処理中です。完了するまでお待ちください。"
        case .appleIdentityMismatch:
            "ログイン中のアカウントと異なるApple IDです。このアプリへのログインに使用したApple IDで、もう一度本人確認してください。"
        case .rejected:
            "削除処理を開始できませんでした。ログイン状態を確認し、もう一度Appleで本人確認してください。"
        case .resultUnknown:
            "アカウントの削除結果を確認できませんでした。削除が完了している可能性があります。通信状態を確認し、結果が分からない場合はお問い合わせください。"
        }
    }

    static func knownRejection(_ error: Error) -> AccountDeletionError? {
        guard case let FunctionsError.httpError(status, data) = error else { return nil }
        struct Payload: Decodable { let code: String? }
        let code = (try? JSONDecoder().decode(Payload.self, from: data))?.code
        if status == 403, code == "apple_identity_mismatch" { return .appleIdentityMismatch }
        // 5xx/relay/transport/decoding errors are not definite failures.
        if [400, 401, 403, 405, 409].contains(status) { return .rejected }
        return nil
    }

    static func requiresLocalSignOut(after error: Error) -> Bool {
        guard let authError = error as? AuthError else { return false }
        return ["user_not_found", "session_not_found", "session_expired",
                "refresh_token_not_found", "refresh_token_already_used",
                "bad_jwt", "invalid_jwt"].contains(authError.errorCode.rawValue)
    }
}
