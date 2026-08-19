import CoreGraphics
import Foundation

@MainActor
final class RemoteSessionModel: ObservableObject {
    @Published private(set) var status: RFBConnectionStatus = .idle
    @Published private(set) var frame: CGImage?
    @Published private(set) var remoteSize: CGSize = .zero

    private var client: RFBClient?

    var isSessionVisible: Bool {
        switch status {
        case .connecting, .negotiating, .authenticating, .connected:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch status {
        case .idle:
            return "Ready"
        case .connecting:
            return "Connecting…"
        case .negotiating:
            return "Negotiating RFB…"
        case .authenticating:
            return "Authenticating…"
        case .connected(let name, let width, let height):
            return "\(name) · \(width)×\(height)"
        case .disconnected:
            return "Disconnected"
        case .failed(let message):
            return message
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = status {
            return message
        }
        return nil
    }

    func connect(host: String, port: UInt16, password: String, rememberPassword: Bool) {
        let endpoint = Self.endpoint(host: host, port: port)
        if rememberPassword {
            try? KeychainStore.save(password: password, for: endpoint)
        } else {
            KeychainStore.deletePassword(for: endpoint)
        }

        frame = nil
        remoteSize = .zero
        let client = RFBClient()
        client.onStatus = { [weak self] status in
            self?.status = status
        }
        client.onFrame = { [weak self] image, size in
            self?.frame = image
            self?.remoteSize = size
        }
        self.client = client
        client.connect(host: host, port: port, password: password)
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        frame = nil
        remoteSize = .zero
        status = .disconnected
    }

    func savedPassword(host: String, port: UInt16) -> String? {
        KeychainStore.password(for: Self.endpoint(host: host, port: port))
    }

    func sendPointer(x: UInt16, y: UInt16, pressed: Bool) {
        client?.sendPointer(x: x, y: y, buttonMask: pressed ? 1 : 0)
    }

    func scroll(up: Bool) {
        client?.sendScroll(up: up)
    }

    func sendText(_ text: String) {
        client?.sendText(text)
    }

    func sendKey(_ keysym: UInt32) {
        client?.sendKey(keysym)
    }

    func refreshScreen() {
        client?.requestFullRefresh()
    }

#if DEBUG
    func prepareUITestSession() {
        guard let buffer = try? RFBFrameBuffer(width: 1_440, height: 900),
              let image = buffer.makeImage() else {
            return
        }
        frame = image
        remoteSize = CGSize(width: 1_440, height: 900)
        status = .connected(name: "Zoom preview", width: 1_440, height: 900)
    }
#endif

    private static func endpoint(host: String, port: UInt16) -> String {
        "\(host.lowercased()):\(port)"
    }
}
