import Foundation

enum ProxmoxError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case notAuthenticated
    case needsTOTP(challenge: String)
    case badCredentials(String?)
    case forbidden(String?)
    case httpStatus(Int, String?)
    case transport(String)
    /// The system does not trust the certificate and nothing has been pinned.
    case untrustedCertificate(host: String, fingerprint: String?)
    /// A certificate was pinned for this server and the one presented differs.
    case certificateChanged(host: String, fingerprint: String?)
    case decoding(String)
    case missingSecret
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address is not valid."
        case .notAuthenticated:
            return "Your session expired. Sign in again."
        case .needsTOTP:
            return "A one-time code is required."
        case .badCredentials(let detail):
            return detail ?? "Proxmox rejected these credentials."
        case .forbidden(let detail):
            return detail ?? "This account doesn't have permission to do that."
        case .httpStatus(let code, let detail):
            return detail.map { "\($0) (HTTP \(code))" } ?? "The server responded with HTTP \(code)."
        case .transport(let message):
            return message
        case .untrustedCertificate(let host, _):
            return "The certificate presented by \(host) isn't trusted."
        case .certificateChanged(let host, _):
            return "The certificate presented by \(host) has changed since you trusted it."
        case .decoding(let message):
            return "The server sent a response Proxyn couldn't read. \(message)"
        case .missingSecret:
            return "No password or token secret is saved for this server."
        case .cancelled:
            return "The request was cancelled."
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .notAuthenticated, .badCredentials: return true
        default: return false
        }
    }

    var certificateFingerprint: String? {
        switch self {
        case .untrustedCertificate(_, let fingerprint), .certificateChanged(_, let fingerprint):
            return fingerprint
        default:
            return nil
        }
    }
}
