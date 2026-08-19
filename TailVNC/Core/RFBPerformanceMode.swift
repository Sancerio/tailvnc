import Foundation

enum RFBPerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case responsive
    case balanced
    case sharp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .responsive: return "Responsive"
        case .balanced: return "Balanced"
        case .sharp: return "Sharp"
        }
    }

    var detail: String {
        switch self {
        case .responsive: return "Lowest latency"
        case .balanced: return "Everyday quality"
        case .sharp: return "Best image"
        }
    }

    var systemImage: String {
        switch self {
        case .responsive: return "hare.fill"
        case .balanced: return "dial.medium.fill"
        case .sharp: return "sparkles.rectangle.stack.fill"
        }
    }

    // RFB Tight JPEG levels are 0...9. Lower quality reduces bandwidth.
    var jpegQualityLevel: Int32 {
        switch self {
        case .responsive: return 2
        case .balanced: return 6
        case .sharp: return 9
        }
    }

    // Keep compression modest in responsive mode to avoid trading network delay
    // for excessive server-side CPU work.
    var compressionLevel: Int32 {
        switch self {
        case .responsive: return 1
        case .balanced: return 4
        case .sharp: return 6
        }
    }

    var jpegQualityEncoding: Int32 { -32 + jpegQualityLevel }
    var compressionEncoding: Int32 { -256 + compressionLevel }

    var orderedEncodings: [Int32] {
        [
            7, // Tight
            0, // Raw fallback
            -223, // DesktopSize
            compressionEncoding,
            jpegQualityEncoding
        ]
    }
}
