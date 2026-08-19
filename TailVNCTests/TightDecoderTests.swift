import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TailVNC

final class TightDecoderTests: XCTestCase {
    func testDecodesFillRectangle() async throws {
        let decoder = try TightDecoder()
        let reader = ByteReader(Data([0x80, 12, 34, 56]))

        let pixels = try await decoder.decodeRectangle(
            width: 2,
            height: 1,
            readExactly: { count in try await reader.read(count) }
        )

        XCTAssertEqual(
            pixels,
            Data([12, 34, 56, 255, 12, 34, 56, 255])
        )
        let isEmpty = await reader.isEmpty
        XCTAssertTrue(isEmpty)
    }

    func testDecodesTwoColorPalette() async throws {
        let decoder = try TightDecoder()
        // Explicit palette filter, two RGB colors, then one bit-packed index byte.
        let reader = ByteReader(Data([
            0x40, 0x01, 0x01,
            255, 0, 0,
            0, 0, 255,
            0b0100_0000
        ]))

        let pixels = try await decoder.decodeRectangle(
            width: 4,
            height: 1,
            readExactly: { count in try await reader.read(count) }
        )

        XCTAssertEqual(
            pixels,
            Data([
                255, 0, 0, 255,
                0, 0, 255, 255,
                255, 0, 0, 255,
                255, 0, 0, 255
            ])
        )
    }

    func testRejectsUnsupportedSubencoding() async throws {
        let decoder = try TightDecoder()
        let reader = ByteReader(Data([0xB0]))

        do {
            _ = try await decoder.decodeRectangle(
                width: 1,
                height: 1,
                readExactly: { count in try await reader.read(count) }
            )
            XCTFail("Expected invalid control")
        } catch let error as TightDecoderError {
            XCTAssertEqual(error, .invalidControl(0xB0))
        }
    }

    func testDecodesPersistentZlibCopyData() async throws {
        let decoder = try TightDecoder()
        let rgb = Data([
            255, 0, 0,
            0, 255, 0,
            0, 0, 255,
            255, 255, 255
        ])
        let compressed = try zlibSyncFlush(rgb)
        var packet = Data([0x00])
        packet.append(compactLength(compressed.count))
        packet.append(compressed)
        let reader = ByteReader(packet)

        let pixels = try await decoder.decodeRectangle(
            width: 2,
            height: 2,
            readExactly: { count in try await reader.read(count) }
        )

        XCTAssertEqual(
            pixels,
            Data([
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
                255, 255, 255, 255
            ])
        )
    }

    func testDecodesJPEGData() async throws {
        let decoder = try TightDecoder()
        let jpeg = try makeJPEG(width: 2, height: 2)
        var packet = Data([0x90])
        packet.append(compactLength(jpeg.count))
        packet.append(jpeg)
        let reader = ByteReader(packet)

        let pixels = try await decoder.decodeRectangle(
            width: 2,
            height: 2,
            readExactly: { count in try await reader.read(count) }
        )

        XCTAssertEqual(pixels.count, 16)
        XCTAssertEqual(Array(pixels.enumerated().compactMap { $0.offset % 4 == 3 ? $0.element : nil }), [255, 255, 255, 255])
    }
}

private func compactLength(_ length: Int) -> Data {
    var value = length
    var result = Data()
    for index in 0..<3 {
        var byte = UInt8(value & 0x7F)
        value >>= 7
        if value > 0 && index < 2 { byte |= 0x80 }
        result.append(byte)
        if value == 0 { break }
    }
    return result
}

private func zlibSyncFlush(_ data: Data) throws -> Data {
    var stream = z_stream()
    let initialize = deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initialize == Z_OK else { throw RFBZlibError.initializationFailed(initialize) }
    defer { deflateEnd(&stream) }

    let outputCapacity = Int(compressBound(uLong(data.count))) + 32
    var output = Data(count: outputCapacity)
    let result = data.withUnsafeBytes { inputBytes in
        output.withUnsafeMutableBytes { outputBytes -> Int32 in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(outputCapacity)
            return deflate(&stream, Z_SYNC_FLUSH)
        }
    }
    guard result == Z_OK else { throw RFBZlibError.decompressionFailed(result) }
    output.removeLast(Int(stream.avail_out))
    return output
}

private func makeJPEG(width: Int, height: Int) throws -> Data {
    let pixels = Data(repeating: 160, count: width * height * 4)
    guard let provider = CGDataProvider(data: pixels as CFData),
          let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        throw TightDecoderError.invalidImage
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw TightDecoderError.invalidImage
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TightDecoderError.invalidImage
    }
    return output as Data
}

private actor ByteReader {
    private var data: Data

    init(_ data: Data) {
        self.data = data
    }

    var isEmpty: Bool { data.isEmpty }

    func read(_ count: Int) throws -> Data {
        guard count >= 0, data.count >= count else {
            throw TightDecoderError.invalidLength
        }
        let prefix = Data(data.prefix(count))
        data.removeFirst(count)
        return prefix
    }
}
