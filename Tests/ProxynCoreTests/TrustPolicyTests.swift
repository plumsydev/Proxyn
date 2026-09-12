import Foundation
import Testing
@testable import ProxynCore

@Suite("TLS trust policy")
struct TrustPolicyTests {
    private let fingerprint = "AB:CD:EF:01"

    @Test("A pin is the trust anchor, whatever the system says")
    func pinOverridesSystem() {
        #expect(TLSTrustDelegate.evaluate(fingerprint: fingerprint, pinned: "abcdef01",
                                          systemTrusts: false, skipVerification: false) == .trusted)
        #expect(TLSTrustDelegate.evaluate(fingerprint: fingerprint, pinned: "00:00",
                                          systemTrusts: true, skipVerification: true) == .pinMismatch)
    }

    @Test("Without a pin, an untrusted certificate is rejected unless verification is off")
    func systemTrustAndSkip() {
        #expect(TLSTrustDelegate.evaluate(fingerprint: fingerprint, pinned: nil,
                                          systemTrusts: true, skipVerification: false) == .trusted)
        #expect(TLSTrustDelegate.evaluate(fingerprint: fingerprint, pinned: nil,
                                          systemTrusts: false, skipVerification: false) == .untrusted)
        #expect(TLSTrustDelegate.evaluate(fingerprint: fingerprint, pinned: nil,
                                          systemTrusts: false, skipVerification: true) == .trusted)
    }

    @Test("Fingerprints are compared ignoring case and separators")
    func normalisation() {
        #expect(TLSTrustDelegate.normalize("ab:cd ef-01") == "ABCDEF01")
    }
}
