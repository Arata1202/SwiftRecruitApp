import Foundation

enum UserFacingError {
    static func message(for error: Error, fallback: String) -> String {
        if error is RepositoryError || error is AuthFlowError {
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
