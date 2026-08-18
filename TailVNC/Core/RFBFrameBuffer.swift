import CoreGraphics
import Foundation

enum RFBFrameBufferError: LocalizedError, Equatable {
    case invalidDimensions
    case rectangleOutOfBounds
    case invalidPixelData

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            return "The server reported invalid display dimensions."
        case .rectangleOutOfBounds:
            return "The server sent a framebuffer rectangle outside the display."
        case .invalidPixelData:
            return "The server sent incomplete framebuffer data."
        }
    }
}

struct RFBFrameBuffer {
    private(set) var width: Int
    private(set) var height: Int
    private(set) var rgba: Data

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
            throw RFBFrameBufferError.invalidDimensions
        }
        self.width = width
        self.height = height
        self.rgba = Data(repeating: 0, count: width * height * 4)
    }

    mutating func resize(width: Int, height: Int) throws {
        self = try RFBFrameBuffer(width: width, height: height)
    }

    mutating func applyRawBGRA(
        x: Int,
        y: Int,
        width rectangleWidth: Int,
        height rectangleHeight: Int,
        pixels: Data
    ) throws {
        guard x >= 0, y >= 0,
              rectangleWidth >= 0, rectangleHeight >= 0,
              x + rectangleWidth <= width,
              y + rectangleHeight <= height else {
            throw RFBFrameBufferError.rectangleOutOfBounds
        }
        guard pixels.count == rectangleWidth * rectangleHeight * 4 else {
            throw RFBFrameBufferError.invalidPixelData
        }

        rgba.withUnsafeMutableBytes { destinationBytes in
            pixels.withUnsafeBytes { sourceBytes in
                guard let destination = destinationBytes.bindMemory(to: UInt8.self).baseAddress,
                      let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                for row in 0..<rectangleHeight {
                    for column in 0..<rectangleWidth {
                        let sourceOffset = (row * rectangleWidth + column) * 4
                        let destinationOffset = ((y + row) * width + x + column) * 4
                        destination[destinationOffset] = source[sourceOffset + 2]
                        destination[destinationOffset + 1] = source[sourceOffset + 1]
                        destination[destinationOffset + 2] = source[sourceOffset]
                        destination[destinationOffset + 3] = 255
                    }
                }
            }
        }
    }

    func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: rgba as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
