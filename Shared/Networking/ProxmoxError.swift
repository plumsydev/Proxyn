import Foundation

enum ProxmoxError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case notAuthenticated
    case needsTOTP(challenge: String)
    case badCredentials(String?)
    case forbidden(String?)
    case httpStatus(Int, String?)
    case transport(String)
    case tlsRejected(host: String, fingerprint: String?)
    case decoding(String)
    case missingSecret
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Adresse du serveur invalide."
        case .notAuthenticated:
            return "Session expirée. Reconnexion nécessaire."
        case .needsTOTP:
            return "Code à usage unique requis."
        case .badCredentials(let detail):
            return detail ?? "Identifiants refusés par Proxmox."
        case .forbidden(let detail):
            return detail ?? "Permissions insuffisantes pour cette action."
        case .httpStatus(let code, let detail):
            return detail.map { "\($0) (HTTP \(code))" } ?? "Le serveur a répondu HTTP \(code)."
        case .transport(let msg):
            return msg
        case .tlsRejected(let host, _):
            return "Certificat TLS de \(host) refusé. Activez le certificat auto-signé dans les réglages du serveur."
        case .decoding(let msg):
            return "Réponse illisible : \(msg)"
        case .missingSecret:
            return "Aucun mot de passe / secret enregistré pour ce serveur."
        case .cancelled:
            return "Requête annulée."
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .notAuthenticated, .badCredentials: return true
        default: return false
        }
    }
}
