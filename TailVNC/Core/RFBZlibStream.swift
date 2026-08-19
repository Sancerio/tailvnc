import Foundation

enum RFBZlibError: LocalizedError, Equatable {
    case initializationFailed(Int32)
    case resetFailed(Int32)
    case decompressionFailed(Int32)
    case incompleteOutput

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let code):
            return "Could not initialize the VNC decompressor (zlib \(code))."
        case .resetFailed(let code):
            return "Could not reset the VNC decompressor (zlib \(code))."
        case .decompressionFailed(let code):
            return "Could not decompress the VNC update (zlib \(code))."
        case .incompleteOutput:
            return "The VNC server sent an incomplete compressed update."
        }
    }
}

final class RFBZlibStream: @unchecked Sendable {
    private var stream = z_stream()
    private var initialized = false

    init() throws {
        let result = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard result == Z_OK else {
            throw RFBZlibError.initializationFailed(result)
        }
        initialized = true
    }

    deinit {
        if initialized {
            inflateEnd(&stream)
        }
    }

    func reset() throws {
        let result = inflateReset(&stream)
        guard result == Z_OK else {
            throw RFBZlibError.resetFailed(result)
        }
    }

    func decompress(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw RFBZlibError.incompleteOutput }
        if expectedSize == 0 { return Data() }

        var output = Data(count: expectedSize)
        let result: Int32 = compressed.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(compressed.count)
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(expectedSize)

                var status = Int32(Z_OK)
                while stream.avail_out > 0 {
                    status = inflate(&stream, Z_SYNC_FLUSH)
                    if status == Z_STREAM_END || status < Z_OK || stream.avail_in == 0 {
                        break
                    }
                }
                return status
            }
        }

        guard result == Z_OK || result == Z_STREAM_END || result == Z_BUF_ERROR else {
            throw RFBZlibError.decompressionFailed(result)
        }
        guard stream.avail_out == 0 else {
            throw RFBZlibError.incompleteOutput
        }
        return output
    }
}
