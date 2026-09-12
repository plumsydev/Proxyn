import Foundation
import CryptoKit

/// Server-trust policy, in order of precedence:
///
/// 1. A pinned SHA-256 fingerprint is the trust anchor: the leaf must match it,
///    whatever the system thinks. This is how self-signed Proxmox certificates
///    are trusted safely (trust on first use).
/// 2. Otherwise the system trust store decides.
/// 3. Only if the user explicitly turned verification off is anything accepted.
final class TLSTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    enum Outcome: Sendable, Equatable {
        case none
        case trusted
        case untrusted
        case pinMismatch
    }

    private let skipVerification: Bool
    private let pinnedFingerprint: String?

    // URLSession calls the delegate on its own queue while the client actor
    // reads these, hence the lock.
    private let lock = NSLock()
    private var _lastFingerprint: String?
    private var _lastOutcome: Outcome = .none

    var lastSeenFingerprint: String? { lock.withLock { _lastFingerprint } }
    var lastOutcome: Outcome { lock.withLock { _lastOutcome } }

    init(skipVerification: Bool, pinnedFingerprint: String?) {
        self.skipVerification = skipVerification
        let pin = pinnedFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pinnedFingerprint = (pin?.isEmpty ?? true) ? nil : pin
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        let fingerprint = Self.leafFingerprint(of: trust)
        let outcome = Self.evaluate(fingerprint: fingerprint,
                                    pinned: pinnedFingerprint,
                                    systemTrusts: SecTrustEvaluateWithError(trust, nil),
                                    skipVerification: skipVerification)
        lock.withLock {
            _lastFingerprint = fingerprint
            _lastOutcome = outcome
        }

        return outcome == .trusted
            ? (.useCredential, URLCredential(trust: trust))
            : (.cancelAuthenticationChallenge, nil)
    }

    /// Pure policy, kept separate so it can be unit-tested.
    static func evaluate(fingerprint: String?, pinned: String?,
                         systemTrusts: Bool, skipVerification: Bool) -> Outcome {
        if let pinned {
            guard let fingerprint else { return .pinMismatch }
            return normalize(fingerprint) == normalize(pinned) ? .trusted : .pinMismatch
        }
        if systemTrusts || skipVerification { return .trusted }
        return .untrusted
    }

    static func normalize(_ fingerprint: String) -> String {
        fingerprint.uppercased().filter { $0.isHexDigit }
    }

    /// Uppercase, colon-separated SHA-256 of the leaf certificate — the format
    /// Proxmox shows under Node → System → Certificates.
    static func leafFingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        return fingerprint(ofDER: SecCertificateCopyData(leaf) as Data)
    }

    static func fingerprint(ofDER data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
