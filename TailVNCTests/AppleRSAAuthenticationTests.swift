import Foundation
import Security
import XCTest
@testable import TailVNC

final class AppleRSAAuthenticationTests: XCTestCase {
    func testBuildsDecryptableAppleCredentialPacket() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2_048
        ]
        var error: Unmanaged<CFError>?
        let privateKey = try XCTUnwrap(
            SecKeyCreateRandomKey(attributes as CFDictionary, &error),
            error?.takeRetainedValue().localizedDescription ?? "RSA generation failed"
        )
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
        let spki = subjectPublicKeyInfo(wrapping: pkcs1)
        let aesKey = Data(0..<16)
        let padding = Data(repeating: 0xa5, count: 116)

        let response = try AppleRSAAuthentication.response(
            publicKeyDER: spki,
            username: "user",
            password: "secret",
            aesKey: aesKey,
            padding: padding
        )

        XCTAssertEqual(try response.uint32BE(at: 0), UInt32(response.count - 4))
        XCTAssertEqual(response[4..<12], Data([1, 0]) + Data("RSA1".utf8) + Data([0, 1]))
        XCTAssertEqual(response[140..<142], Data([0, 1]))

        let decryptedCredentials = try AppleRSAAuthentication.decryptCredentialsForTesting(
            Data(response[12..<140]),
            aesKey: aesKey
        )
        XCTAssertEqual(decryptedCredentials.prefix(5), Data([117, 115, 101, 114, 0]))
        XCTAssertEqual(decryptedCredentials[64..<71], Data([115, 101, 99, 114, 101, 116, 0]))

        let encryptedKey = Data(response[142...])
        let decryptedKey = try XCTUnwrap(
            SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, encryptedKey as CFData, &error)
                as Data?,
            error?.takeRetainedValue().localizedDescription ?? "RSA decryption failed"
        )
        XCTAssertEqual(decryptedKey, aesKey)
    }

    func testRejectsMalformedServerKey() {
        XCTAssertThrowsError(
            try AppleRSAAuthentication.response(
                publicKeyDER: Data([0, 1, 2]),
                username: "user",
                password: "secret"
            )
        )
    }

    private func subjectPublicKeyInfo(wrapping pkcs1: Data) -> Data {
        let rsaAlgorithmIdentifier = Data([
            0x30, 0x0d,
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00
        ])
        return der(tag: 0x30, value: rsaAlgorithmIdentifier + der(tag: 0x03, value: Data([0]) + pkcs1))
    }

    private func der(tag: UInt8, value: Data) -> Data {
        var result = Data([tag])
        if value.count < 128 {
            result.append(UInt8(value.count))
        } else {
            let bytes = withUnsafeBytes(of: UInt32(value.count).bigEndian) { Data($0) }
                .drop(while: { $0 == 0 })
            result.append(0x80 | UInt8(bytes.count))
            result.append(contentsOf: bytes)
        }
        result.append(value)
        return result
    }
}
