import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TightDecoderError: LocalizedError, Equatable {
    case invalidControl(UInt8)
    case invalidFilter(UInt8)
    case invalidLength
    case invalidImage
    case invalidPalette

    var errorDescription: String? {
        switch self {
        case .invalidControl(let value):
            return "The VNC server sent an unsupported Tight control byte \(value)."
        case .invalidFilter(let value):
            return "The VNC server sent an unsupported Tight filter \(value)."
        case .invalidLength:
            return "The VNC server sent invalid Tight update lengths."
        case .invalidImage:
            return "The VNC server sent an invalid Tight JPEG image."
        case .invalidPalette:
            return "The VNC server sent an invalid Tight color palette."
        }
    }
}

final class TightDecoder: @unchecked Sendable {
    typealias Reader = @Sendable (Int) async throws -> Data

    private var streams: [RFBZlibStream]

    init() throws {
        streams = try (0..<4).map { _ in try RFBZlibStream() }
    }

    func decodeRectangle(
        width: Int,
        height: Int,
        readExactly: Reader
    ) async throws -> Data {
        guard width > 0, height > 0 else { return Data() }

        let control = try await readByte(readExactly)
        for index in 0..<4 where control & UInt8(1 << index) != 0 {
            try streams[index].reset()
        }

        let subencoding = control & 0xF0
        switch subencoding {
        case 0x80:
            let pixel = try await readExactly(3)
            return try Self.filledRGBA(pixel: pixel, count: width * height)
        case 0x90:
            let length = try await readCompactLength(readExactly)
            guard length > 0 else { throw TightDecoderError.invalidLength }
            let jpeg = try await readExactly(length)
            return try Self.decodeJPEG(jpeg, width: width, height: height)
        default:
            guard control & 0x80 == 0 else {
                throw TightDecoderError.invalidControl(control)
            }
            return try await decodeBasic(
                control: control,
                width: width,
                height: height,
                readExactly: readExactly
            )
        }
    }

    private func decodeBasic(
        control: UInt8,
        width: Int,
        height: Int,
        readExactly: Reader
    ) async throws -> Data {
        let streamID = Int((control >> 4) & 0x03)
        let filter = control & 0x40 == 0 ? UInt8(0) : try await readByte(readExactly)

        switch filter {
        case 0:
            let expected = width * height * 3
            let rgb = try await readBasicData(
                expectedSize: expected,
                streamID: streamID,
                readExactly: readExactly
            )
            return try Self.rgbToRGBA(rgb)
        case 1:
            let paletteSize = Int(try await readByte(readExactly)) + 1
            guard (2...256).contains(paletteSize) else {
                throw TightDecoderError.invalidPalette
            }
            let palette = try await readExactly(paletteSize * 3)
            let expectedIndices = paletteSize == 2
                ? ((width + 7) / 8) * height
                : width * height
            let indices = try await readBasicData(
                expectedSize: expectedIndices,
                streamID: streamID,
                readExactly: readExactly
            )
            return try Self.expandPalette(
                indices: indices,
                palette: palette,
                paletteSize: paletteSize,
                width: width,
                height: height
            )
        case 2:
            let expected = width * height * 3
            let filtered = try await readBasicData(
                expectedSize: expected,
                streamID: streamID,
                readExactly: readExactly
            )
            return try Self.decodeGradient(filtered, width: width, height: height)
        default:
            throw TightDecoderError.invalidFilter(filter)
        }
    }

    private func readBasicData(
        expectedSize: Int,
        streamID: Int,
        readExactly: Reader
    ) async throws -> Data {
        guard expectedSize >= 0 else { throw TightDecoderError.invalidLength }
        if expectedSize < 12 {
            return try await readExactly(expectedSize)
        }
        let compressedSize = try await readCompactLength(readExactly)
        guard compressedSize > 0 else { throw TightDecoderError.invalidLength }
        let compressed = try await readExactly(compressedSize)
        return try streams[streamID].decompress(compressed, expectedSize: expectedSize)
    }

    private func readCompactLength(_ readExactly: Reader) async throws -> Int {
        var length = 0
        var shift = 0
        for _ in 0..<3 {
            let byte = try await readByte(readExactly)
            length |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return length }
            shift += 7
        }
        throw TightDecoderError.invalidLength
    }

    private func readByte(_ readExactly: Reader) async throws -> UInt8 {
        let data = try await readExactly(1)
        guard let byte = data.first else { throw TightDecoderError.invalidLength }
        return byte
    }

    static func filledRGBA(pixel: Data, count: Int) throws -> Data {
        guard pixel.count == 3, count >= 0 else { throw TightDecoderError.invalidLength }
        var output = Data(count: count * 4)
        output.withUnsafeMutableBytes { bytes in
            guard let target = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<count {
                let offset = index * 4
                target[offset] = pixel[0]
                target[offset + 1] = pixel[1]
                target[offset + 2] = pixel[2]
                target[offset + 3] = 255
            }
        }
        return output
    }

    static func rgbToRGBA(_ rgb: Data) throws -> Data {
        guard rgb.count % 3 == 0 else { throw TightDecoderError.invalidLength }
        var output = Data(count: rgb.count / 3 * 4)
        output.withUnsafeMutableBytes { bytes in
            guard let target = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            rgb.withUnsafeBytes { sourceBytes in
                guard let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return }
                for index in 0..<(rgb.count / 3) {
                    target[index * 4] = source[index * 3]
                    target[index * 4 + 1] = source[index * 3 + 1]
                    target[index * 4 + 2] = source[index * 3 + 2]
                    target[index * 4 + 3] = 255
                }
            }
        }
        return output
    }

    static func expandPalette(
        indices: Data,
        palette: Data,
        paletteSize: Int,
        width: Int,
        height: Int
    ) throws -> Data {
        guard palette.count == paletteSize * 3 else {
            throw TightDecoderError.invalidPalette
        }
        let pixelCount = width * height
        var output = Data(count: pixelCount * 4)
        var invalid = false

        output.withUnsafeMutableBytes { bytes in
            guard let target = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in 0..<height {
                for column in 0..<width {
                    let pixelIndex = row * width + column
                    let paletteIndex: Int
                    if paletteSize == 2 {
                        let bytesPerRow = (width + 7) / 8
                        let byte = indices[row * bytesPerRow + column / 8]
                        paletteIndex = Int((byte >> (7 - column % 8)) & 1)
                    } else {
                        paletteIndex = Int(indices[pixelIndex])
                    }
                    guard paletteIndex < paletteSize else {
                        invalid = true
                        return
                    }
                    let source = paletteIndex * 3
                    let destination = pixelIndex * 4
                    target[destination] = palette[source]
                    target[destination + 1] = palette[source + 1]
                    target[destination + 2] = palette[source + 2]
                    target[destination + 3] = 255
                }
            }
        }
        if invalid { throw TightDecoderError.invalidPalette }
        return output
    }

    static func decodeGradient(_ data: Data, width: Int, height: Int) throws -> Data {
        guard data.count == width * height * 3 else {
            throw TightDecoderError.invalidLength
        }
        var output = Data(count: width * height * 4)
        var previous = [[Int]](repeating: [Int](repeating: 0, count: width), count: 3)
        var current = previous

        output.withUnsafeMutableBytes { bytes in
            guard let target = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            var sourceIndex = 0
            for row in 0..<height {
                var left = [0, 0, 0]
                for column in 0..<width {
                    let destination = (row * width + column) * 4
                    for component in 0..<3 {
                        let up = previous[component][column]
                        let upLeft = column > 0 ? previous[component][column - 1] : 0
                        let prediction = min(255, max(0, left[component] + up - upLeft))
                        let value = (Int(data[sourceIndex]) + prediction) & 0xFF
                        sourceIndex += 1
                        current[component][column] = value
                        left[component] = value
                        target[destination + component] = UInt8(value)
                    }
                    target[destination + 3] = 255
                }
                swap(&previous, &current)
                current = [[Int]](repeating: [Int](repeating: 0, count: width), count: 3)
            }
        }
        return output
    }

    static func decodeJPEG(_ data: Data, width: Int, height: Int) throws -> Data {
        let options = [
            kCGImageSourceTypeIdentifierHint: UTType.jpeg.identifier as CFString
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width,
              image.height == height else {
            throw TightDecoderError.invalidImage
        }

        var output = Data(count: width * height * 4)
        let rendered = output.withUnsafeMutableBytes { bytes -> Bool in
            guard let base = bytes.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                        CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw TightDecoderError.invalidImage }
        return output
    }
}
