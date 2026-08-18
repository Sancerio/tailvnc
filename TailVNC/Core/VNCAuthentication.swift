import Foundation

enum VNCAuthenticationError: LocalizedError, Equatable {
    case invalidChallengeLength

    var errorDescription: String? {
        switch self {
        case .invalidChallengeLength:
            return "The VNC server sent an invalid authentication challenge."
        }
    }
}

enum VNCAuthentication {
    static func response(challenge: Data, password: String) throws -> Data {
        guard challenge.count == 16 else {
            throw VNCAuthenticationError.invalidChallengeLength
        }

        var keyBytes = Array(password.utf8.prefix(8))
        keyBytes.append(contentsOf: repeatElement(0, count: max(0, 8 - keyBytes.count)))
        keyBytes = keyBytes.map(reverseBits)
        let key = uint64(from: keyBytes[0..<8])

        var response = Data()
        for offset in stride(from: 0, to: 16, by: 8) {
            let block = uint64(from: Array(challenge[offset..<(offset + 8)])[0..<8])
            let encrypted = DES.encrypt(block: block, key: key)
            response.append(contentsOf: bytes(from: encrypted))
        }
        return response
    }

    private static func reverseBits(_ byte: UInt8) -> UInt8 {
        var input = byte
        var output: UInt8 = 0
        for _ in 0..<8 {
            output = (output << 1) | (input & 1)
            input >>= 1
        }
        return output
    }

    private static func uint64(from bytes: ArraySlice<UInt8>) -> UInt64 {
        bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private static func bytes(from value: UInt64) -> [UInt8] {
        (0..<8).map { index in
            UInt8((value >> UInt64((7 - index) * 8)) & 0xff)
        }
    }
}
