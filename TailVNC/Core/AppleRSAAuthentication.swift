import Foundation
import Security

enum AppleRSAAuthenticationError: LocalizedError, Equatable {
    case invalidServerKey
    case invalidAESKey
    case randomGenerationFailed(OSStatus)
    case credentialEncryptionFailed(CCCryptorStatus)
    case keyEncryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerKey:
            return "The Mac sent an invalid Screen Sharing public key."
        case .invalidAESKey:
            return "Screen Sharing generated an invalid encryption key."
        case .randomGenerationFailed(let status):
            return "Secure random generation failed (\(status))."
        case .credentialEncryptionFailed(let status):
            return "Credential encryption failed (\(status))."
        case .keyEncryptionFailed(let message):
            return "Screen Sharing key encryption failed: \(message)"
        }
    }
}

enum AppleRSAAuthentication {
    static let securityType: UInt8 = 33

    static var keyRequest: Data {
        var packet = Data()
        packet.appendUInt32BE(10)
        packet.append(contentsOf: [1, 0])
        packet.append(Data("RSA1".utf8))
        packet.append(contentsOf: [0, 0, 0, 0])
        return packet
    }

    static func response(
        publicKeyDER: Data,
        username: String,
        password: String,
        aesKey suppliedAESKey: Data? = nil,
        padding suppliedPadding: Data? = nil
    ) throws -> Data {
        let publicKey = try rsaPublicKey(fromSPKI: publicKeyDER)
        let aesKey = try suppliedAESKey ?? secureRandom(count: kCCKeySizeAES128)
        guard aesKey.count == kCCKeySizeAES128 else {
            throw AppleRSAAuthenticationError.invalidAESKey
        }

        let requiredPadding = paddingCount(for: username) + paddingCount(for: password)
        let padding = try suppliedPadding ?? secureRandom(count: requiredPadding)
        guard padding.count == requiredPadding else {
            throw AppleRSAAuthenticationError.invalidAESKey
        }
        var paddingOffset = 0
        let packedUsername = packCredential(username, padding: padding, offset: &paddingOffset)
        let packedPassword = packCredential(password, padding: padding, offset: &paddingOffset)
        let encryptedCredentials = try aesECB(
            packedUsername + packedPassword,
            key: aesKey,
            operation: CCOperation(kCCEncrypt)
        )

        var keyError: Unmanaged<CFError>?
        guard let encryptedKey = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionPKCS1,
            aesKey as CFData,
            &keyError
        ) as Data? else {
            let message = keyError?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw AppleRSAAuthenticationError.keyEncryptionFailed(message)
        }

        var content = Data([1, 0])
        content.append(Data("RSA1".utf8))
        content.append(contentsOf: [0, 1])
        content.append(encryptedCredentials)
        content.append(contentsOf: [0, 1])
        content.append(encryptedKey)

        var packet = Data()
        packet.appendUInt32BE(UInt32(content.count))
        packet.append(content)
        return packet
    }

    static func decryptCredentialsForTesting(_ data: Data, aesKey: Data) throws -> Data {
        try aesECB(data, key: aesKey, operation: CCOperation(kCCDecrypt))
    }

    private static func rsaPublicKey(fromSPKI der: Data) throws -> SecKey {
        var outer = DERReader(data: der)
        let sequence = try outer.read(tag: 0x30)
        guard outer.isAtEnd else { throw AppleRSAAuthenticationError.invalidServerKey }

        var body = DERReader(data: sequence)
        _ = try body.read(tag: 0x30)
        let bitString = try body.read(tag: 0x03)
        guard body.isAtEnd, bitString.first == 0 else {
            throw AppleRSAAuthenticationError.invalidServerKey
        }
        let pkcs1 = Data(bitString.dropFirst())
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            throw AppleRSAAuthenticationError.invalidServerKey
        }
        return key
    }

    private static func secureRandom(count: Int) throws -> Data {
        guard count >= 0 else { throw AppleRSAAuthenticationError.invalidAESKey }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AppleRSAAuthenticationError.randomGenerationFailed(status)
        }
        return data
    }

    private static func paddingCount(for credential: String) -> Int {
        min(Data(credential.utf8).count + 1, 64) < 64
            ? 64 - min(Data(credential.utf8).count + 1, 64)
            : 0
    }

    private static func packCredential(
        _ credential: String,
        padding: Data,
        offset: inout Int
    ) -> Data {
        var packed = Data(credential.utf8)
        packed.append(0)
        if packed.count >= 64 {
            return Data(packed.prefix(64))
        }
        let count = 64 - packed.count
        packed.append(padding[offset..<(offset + count)])
        offset += count
        return packed
    }

    private static func aesECB(_ data: Data, key: Data, operation: CCOperation) throws -> Data {
        guard key.count == kCCKeySizeAES128, data.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw AppleRSAAuthenticationError.invalidAESKey
        }
        var output = Data(count: data.count)
        let outputCount = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        inputBuffer.baseAddress,
                        data.count,
                        outputBuffer.baseAddress,
                        outputCount,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess, moved == data.count else {
            throw AppleRSAAuthenticationError.credentialEncryptionFailed(status)
        }
        return output
    }
}

private struct DERReader {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool { offset == data.count }

    mutating func read(tag expectedTag: UInt8) throws -> Data {
        guard offset < data.count, data[offset] == expectedTag else {
            throw AppleRSAAuthenticationError.invalidServerKey
        }
        offset += 1
        let length = try readLength()
        guard length >= 0, offset + length <= data.count else {
            throw AppleRSAAuthenticationError.invalidServerKey
        }
        let value = data.subdata(in: offset..<(offset + length))
        offset += length
        return value
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else { throw AppleRSAAuthenticationError.invalidServerKey }
        let first = Int(data[offset])
        offset += 1
        if first & 0x80 == 0 { return first }
        let byteCount = first & 0x7f
        guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else {
            throw AppleRSAAuthenticationError.invalidServerKey
        }
        var length = 0
        for _ in 0..<byteCount {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }
}
