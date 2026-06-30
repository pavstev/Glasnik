import CryptoKit
import XCTest
@testable import Sapat

/// The updater's fail-closed trust chain (F3). This is the explicit acceptance test: a missing
/// or tampered signature must be refused, and only a valid ed25519 signature over the exact
/// bytes is accepted.
final class UpdateVerificationTests: XCTestCase {
    private func keypair() -> (priv: Curve25519.Signing.PrivateKey, pubB64: String) {
        let priv = Curve25519.Signing.PrivateKey()
        return (priv, priv.publicKey.rawRepresentation.base64EncodedString())
    }

    func testValidSignatureVerifies() throws {
        let (priv, pub) = keypair()
        let data = Data("Sapat-1.2.3.zip bytes".utf8)
        let signature = try priv.signature(for: data)
        XCTAssertTrue(ReleaseSignature.verify(data: data, signature: signature, publicKeyBase64: pub))
        XCTAssertNoThrow(try ReleaseSignature.gate(data: data, signature: signature, publicKeyBase64: pub))
    }

    func testTamperedArtifactIsRejected() throws {
        let (priv, pub) = keypair()
        let signed = Data("the real build".utf8)
        let signature = try priv.signature(for: signed)
        let tampered = Data("a malicious build".utf8)
        XCTAssertFalse(ReleaseSignature.verify(data: tampered, signature: signature, publicKeyBase64: pub))
        XCTAssertThrowsError(try ReleaseSignature.gate(data: tampered, signature: signature, publicKeyBase64: pub)) {
            XCTAssertEqual($0 as? ReleaseSignature.SignatureError, .invalid)
        }
    }

    func testMissingSignatureFailsClosed() {
        // The core acceptance: no signature ⇒ no install.
        XCTAssertThrowsError(try ReleaseSignature.gate(data: Data("x".utf8), signature: nil)) {
            XCTAssertEqual($0 as? ReleaseSignature.SignatureError, .missing)
        }
        XCTAssertThrowsError(try ReleaseSignature.gate(data: Data("x".utf8), signature: Data())) {
            XCTAssertEqual($0 as? ReleaseSignature.SignatureError, .missing)
        }
    }

    func testWrongKeyIsRejected() throws {
        let (priv, _) = keypair()
        let (_, otherPub) = keypair()
        let data = Data("build".utf8)
        let signature = try priv.signature(for: data)
        XCTAssertFalse(ReleaseSignature.verify(data: data, signature: signature, publicKeyBase64: otherPub))
    }

    func testMalformedSignatureLengthRejected() {
        XCTAssertFalse(ReleaseSignature.verify(
            data: Data("x".utf8), signature: Data([1, 2, 3]), publicKeyBase64: ReleaseSignature.publicKeyBase64))
    }

    func testEmbeddedPublicKeyIsValid() {
        let decoded = Data(base64Encoded: ReleaseSignature.publicKeyBase64)
        XCTAssertEqual(decoded?.count, 32, "embedded ed25519 public key must be 32 bytes")
    }

    func testSignatureAssetDetectionGatesUnsignedReleases() {
        let signed = [
            UpdateChecker.ReleaseAsset(name: "Sapat-2.0.0.zip", browserDownloadURL: "https://x/Sapat-2.0.0.zip"),
            UpdateChecker.ReleaseAsset(name: "Sapat-2.0.0.zip.sig", browserDownloadURL: "https://x/Sapat-2.0.0.zip.sig"),
        ]
        XCTAssertNotNil(UpdateChecker.signatureAsset(from: signed))
        // An unsigned release (no .sig) has no signature asset → the updater skips it quietly.
        let unsigned = [UpdateChecker.ReleaseAsset(name: "Sapat-1.6.0.zip", browserDownloadURL: "https://x/Sapat-1.6.0.zip")]
        XCTAssertNil(UpdateChecker.signatureAsset(from: unsigned))
    }

    func testParseSignatureAcceptsBase64AndRaw() {
        let raw = Data((0..<64).map { UInt8($0 & 0xff) })
        XCTAssertEqual(ReleaseSignature.parseSignature(Data(raw.base64EncodedString().utf8)), raw)
        XCTAssertEqual(ReleaseSignature.parseSignature(raw), raw)
        XCTAssertNil(ReleaseSignature.parseSignature(Data("not a signature".utf8)))
    }
}
