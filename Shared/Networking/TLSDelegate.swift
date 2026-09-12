import Foundation
import CryptoKit

/// Homelabs run self-signed certificates. We support two modes, both explicit:
/// trust-on-first-use pinning (preferred) and a blanket "accept self-signed"
/// switch that the user has to flip per server.
final class TLSTrustDelegate: NSObject, URLSessionDelegate {
    private let allowInsecure: Bool
    private let pinnedFingerprint: String?
    /// Set on the first handshake so the UI can offer to pin it.
    private(set) var lastSeenFingerprint: String?

    init(allowInsecure: Bool, pinnedFingerprint: String?) {
        self.allowInsecure = allowInsecure
        self.pinnedFingerprint = pinnedFingerprint
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let fingerprint = Self.leafFingerprint(of: trust)
        lastSeenFingerprint = fingerprint

        if let pinnedFingerprint, !pinnedFingerprint.isEmpty {
            if let fingerprint,
               fingerprint.caseInsensitiveCompare(pinnedFingerprint) == .orderedSame {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        if allowInsecure {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Uppercase hex SHA-256 of the leaf certificate, colon-separated — the same
    /// shape Proxmox prints in its web UI.
    static func leafFingerprint(of trust: SecTrust) -> String? {
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        guard let leaf = chain?.first else { return nil }
        let data = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
