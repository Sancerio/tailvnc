import CoreGraphics
import Foundation

@MainActor
final class RemoteSessionModel: ObservableObject {
    @Published private(set) var status: RFBConnectionStatus = .idle
    @Published private(set) var frame: CGImage?
    @Published private(set) var remoteSize: CGSize = .zero
    @Published private(set) var performanceMode: RFBPerformanceMode = .responsive
    @Published private(set) var inputActivitySequence = 0

    private var client: RFBClient?
    private var pointerWasPressed = false

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

    func connect(
        host: String,
        port: UInt16,
        authentication: RFBAuthentication,
        rememberCredentials: Bool
    ) {
        let endpoint = Self.endpoint(host: host, port: port)
        switch authentication {
        case .macAccount(let username, let password):
            if rememberCredentials {
                try? KeychainStore.save(
                    macCredentials: MacCredentials(username: username, password: password),
                    for: endpoint
                )
            } else {
                KeychainStore.deleteMacCredentials(for: endpoint)
            }
        case .vncPassword(let password):
            if rememberCredentials {
                try? KeychainStore.save(password: password, for: endpoint)
            } else {
                KeychainStore.deletePassword(for: endpoint)
            }
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
        client.connect(
            host: host,
            port: port,
            authentication: authentication,
            performanceMode: performanceMode
        )
    }

    func disconnect() {
        client?.disconnect()
        client = nil
        frame = nil
        remoteSize = .zero
        pointerWasPressed = false
        status = .disconnected
    }

    func savedPassword(host: String, port: UInt16) -> String? {
        KeychainStore.password(for: Self.endpoint(host: host, port: port))
    }

    func savedMacCredentials(host: String, port: UInt16) -> MacCredentials? {
        KeychainStore.macCredentials(for: Self.endpoint(host: host, port: port))
    }

    func sendPointer(x: UInt16, y: UInt16, pressed: Bool) {
        if pressed && !pointerWasPressed {
            markInputActivity()
        }
        pointerWasPressed = pressed
        client?.sendPointer(x: x, y: y, buttonMask: pressed ? 1 : 0)
    }

    func scroll(up: Bool) {
        markInputActivity()
        client?.sendScroll(up: up)
    }

    func sendText(_ text: String) {
        if !text.isEmpty {
            markInputActivity()
        }
        client?.sendText(text)
    }

    func sendKey(_ keysym: UInt32) {
        markInputActivity()
        client?.sendKey(keysym)
    }

    func setPerformanceMode(_ mode: RFBPerformanceMode) {
        guard performanceMode != mode else { return }
        performanceMode = mode
        client?.setPerformanceMode(mode)
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

    private func markInputActivity() {
        inputActivitySequence &+= 1
    }
}
