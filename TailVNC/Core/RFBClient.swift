import CoreGraphics
import Foundation
import Network

enum RFBConnectionStatus: Equatable {
    case idle
    case connecting
    case negotiating
    case authenticating
    case connected(name: String, width: Int, height: Int)
    case disconnected
    case failed(String)
}

enum RFBClientError: LocalizedError {
    case invalidHost
    case invalidPort
    case connectionFailed(String)
    case unexpectedEndOfStream
    case invalidProtocolVersion(String)
    case serverRejected(String)
    case vncAuthenticationUnavailable([UInt8])
    case authenticationFailed(String)
    case unsupportedServerMessage(UInt8)
    case unsupportedEncoding(Int32)
    case malformedMessage

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Enter a valid host or IP address."
        case .invalidPort:
            return "Enter a TCP port between 1 and 65535."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .unexpectedEndOfStream:
            return "The VNC server closed the connection."
        case .invalidProtocolVersion(let value):
            return "Unsupported RFB greeting: \(value)"
        case .serverRejected(let reason):
            return "The VNC server rejected the connection: \(reason)"
        case .vncAuthenticationUnavailable(let types):
            return "The server does not offer standard VNC authentication (types: \(types))."
        case .authenticationFailed(let reason):
            return "VNC authentication failed: \(reason)"
        case .unsupportedServerMessage(let type):
            return "The server sent unsupported message type \(type)."
        case .unsupportedEncoding(let encoding):
            return "The server sent unsupported framebuffer encoding \(encoding)."
        case .malformedMessage:
            return "The VNC server sent a malformed protocol message."
        }
    }
}

final class RFBClient: @unchecked Sendable {
    var onStatus: ((RFBConnectionStatus) -> Void)?
    var onFrame: ((CGImage, CGSize) -> Void)?

    private let networkQueue = DispatchQueue(label: "com.sancerio.tailvnc.rfb")
    private var connection: NWConnection?
    private var sessionTask: Task<Void, Never>?
    private var framebuffer: RFBFrameBuffer?
    private var remoteWidth: UInt16 = 0
    private var remoteHeight: UInt16 = 0
    private var lastPointerX: UInt16 = 0
    private var lastPointerY: UInt16 = 0

    func connect(host: String, port: UInt16, password: String) {
        disconnect(notify: false)
        publish(.connecting)
        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(host: host, port: port, password: password)
            } catch is CancellationError {
                self.publish(.disconnected)
            } catch {
                self.publish(.failed(error.localizedDescription))
                self.connection?.cancel()
            }
        }
    }

    func disconnect() {
        disconnect(notify: true)
    }

    private func disconnect(notify: Bool) {
        sessionTask?.cancel()
        sessionTask = nil
        connection?.cancel()
        connection = nil
        framebuffer = nil
        if notify {
            publish(.disconnected)
        }
    }

    func sendPointer(x: UInt16, y: UInt16, buttonMask: UInt8) {
        lastPointerX = x
        lastPointerY = y
        var message = Data([5, buttonMask])
        message.appendUInt16BE(x)
        message.appendUInt16BE(y)
        sendInBackground(message)
    }

    func sendScroll(up: Bool, steps: Int = 2) {
        let mask: UInt8 = up ? 8 : 16
        for _ in 0..<max(1, steps) {
            sendPointer(x: lastPointerX, y: lastPointerY, buttonMask: mask)
            sendPointer(x: lastPointerX, y: lastPointerY, buttonMask: 0)
        }
    }

    func sendKey(_ keysym: UInt32) {
        sendKeyEvent(keysym, isDown: true)
        sendKeyEvent(keysym, isDown: false)
    }

    func sendText(_ text: String) {
        for scalar in text.unicodeScalars {
            let value = scalar.value <= 0xff ? scalar.value : 0x0100_0000 | scalar.value
            sendKey(value)
        }
    }

    private func sendKeyEvent(_ keysym: UInt32, isDown: Bool) {
        var message = Data([4, isDown ? 1 : 0, 0, 0])
        message.appendUInt32BE(keysym)
        sendInBackground(message)
    }

    private func sendInBackground(_ message: Data) {
        Task { [weak self] in
            try? await self?.send(message)
        }
    }

    private func run(host: String, port: UInt16, password: String) async throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RFBClientError.invalidHost
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RFBClientError.invalidPort
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.connection = connection
        try await start(connection)
        publish(.negotiating)

        let greetingData = try await receiveExactly(12)
        guard let greeting = String(data: greetingData, encoding: .ascii),
              greeting.hasPrefix("RFB ") else {
            throw RFBClientError.invalidProtocolVersion(String(decoding: greetingData, as: UTF8.self))
        }
        try await send(Data("RFB 003.008\n".utf8))

        let securityCount = Int(try await receiveExactly(1)[0])
        if securityCount == 0 {
            let reason = try await readLengthPrefixedString()
            throw RFBClientError.serverRejected(reason)
        }
        let securityTypes = Array(try await receiveExactly(securityCount))
        guard securityTypes.contains(2) else {
            throw RFBClientError.vncAuthenticationUnavailable(securityTypes)
        }

        try await send(Data([2]))
        publish(.authenticating)
        let challenge = try await receiveExactly(16)
        let response = try VNCAuthentication.response(challenge: challenge, password: password)
        try await send(response)

        let securityResult = try await receiveExactly(4).uint32BE(at: 0)
        guard securityResult == 0 else {
            let reason = (try? await readLengthPrefixedString()) ?? "password rejected"
            throw RFBClientError.authenticationFailed(reason)
        }

        try await send(Data([1]))
        let serverHeader = try await receiveExactly(24)
        let width = Int(try serverHeader.uint16BE(at: 0))
        let height = Int(try serverHeader.uint16BE(at: 2))
        let nameLength = Int(try serverHeader.uint32BE(at: 20))
        guard nameLength >= 0, nameLength <= 1_048_576 else {
            throw RFBClientError.malformedMessage
        }
        let nameData = try await receiveExactly(nameLength)
        let name = String(data: nameData, encoding: .utf8) ?? "Remote computer"

        remoteWidth = UInt16(width)
        remoteHeight = UInt16(height)
        lastPointerX = UInt16(width / 2)
        lastPointerY = UInt16(height / 2)
        framebuffer = try RFBFrameBuffer(width: width, height: height)

        try await sendPixelFormat()
        try await sendEncodings()
        try await requestFramebufferUpdate(incremental: false)
        publish(.connected(name: name, width: width, height: height))

        while !Task.isCancelled {
            try await receiveServerMessage()
        }
    }

    private func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    continuation.resume()
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: RFBClientError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: networkQueue)
        }
    }

    private func receiveExactly(_ count: Int) async throws -> Data {
        guard count >= 0 else { throw RFBClientError.malformedMessage }
        if count == 0 { return Data() }

        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            let remaining = count - result.count
            let chunk: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                guard let connection else {
                    continuation.resume(throwing: RFBClientError.unexpectedEndOfStream)
                    return
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error {
                        continuation.resume(throwing: RFBClientError.connectionFailed(error.localizedDescription))
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if complete {
                        continuation.resume(throwing: RFBClientError.unexpectedEndOfStream)
                    } else {
                        continuation.resume(throwing: RFBClientError.unexpectedEndOfStream)
                    }
                }
            }
            result.append(chunk)
        }
        return result
    }

    private func send(_ data: Data) async throws {
        try Task.checkCancellation()
        guard let connection else {
            throw RFBClientError.unexpectedEndOfStream
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: RFBClientError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func readLengthPrefixedString() async throws -> String {
        let length = Int(try await receiveExactly(4).uint32BE(at: 0))
        guard length >= 0, length <= 1_048_576 else {
            throw RFBClientError.malformedMessage
        }
        let data = try await receiveExactly(length)
        return String(data: data, encoding: .utf8) ?? "unknown reason"
    }

    private func sendPixelFormat() async throws {
        var message = Data([0, 0, 0, 0])
        message.append(contentsOf: [32, 24, 0, 1])
        message.appendUInt16BE(255)
        message.appendUInt16BE(255)
        message.appendUInt16BE(255)
        message.append(contentsOf: [16, 8, 0, 0, 0, 0])
        try await send(message)
    }

    private func sendEncodings() async throws {
        var message = Data([2, 0])
        message.appendUInt16BE(2)
        message.appendInt32BE(0)
        message.appendInt32BE(-223)
        try await send(message)
    }

    private func requestFramebufferUpdate(incremental: Bool) async throws {
        var message = Data([3, incremental ? 1 : 0])
        message.appendUInt16BE(0)
        message.appendUInt16BE(0)
        message.appendUInt16BE(remoteWidth)
        message.appendUInt16BE(remoteHeight)
        try await send(message)
    }

    private func receiveServerMessage() async throws {
        let type = try await receiveExactly(1)[0]
        switch type {
        case 0:
            try await receiveFramebufferUpdate()
        case 1:
            try await discardColorMap()
        case 2:
            break
        case 3:
            let header = try await receiveExactly(7)
            let length = Int(try header.uint32BE(at: 3))
            guard length >= 0, length <= 16_777_216 else {
                throw RFBClientError.malformedMessage
            }
            _ = try await receiveExactly(length)
        default:
            throw RFBClientError.unsupportedServerMessage(type)
        }
    }

    private func receiveFramebufferUpdate() async throws {
        let header = try await receiveExactly(3)
        let rectangleCount = Int(try header.uint16BE(at: 1))

        for _ in 0..<rectangleCount {
            let rectangle = try await receiveExactly(12)
            let x = Int(try rectangle.uint16BE(at: 0))
            let y = Int(try rectangle.uint16BE(at: 2))
            let width = Int(try rectangle.uint16BE(at: 4))
            let height = Int(try rectangle.uint16BE(at: 6))
            let encoding = Int32(bitPattern: try rectangle.uint32BE(at: 8))

            switch encoding {
            case 0:
                let byteCount = width * height * 4
                guard byteCount >= 0, byteCount <= 1_073_741_824 else {
                    throw RFBClientError.malformedMessage
                }
                let pixels = try await receiveExactly(byteCount)
                try framebuffer?.applyRawBGRA(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    pixels: pixels
                )
            case -223:
                remoteWidth = UInt16(width)
                remoteHeight = UInt16(height)
                try framebuffer?.resize(width: width, height: height)
            default:
                throw RFBClientError.unsupportedEncoding(encoding)
            }
        }

        if let framebuffer, let image = framebuffer.makeImage() {
            let size = CGSize(width: framebuffer.width, height: framebuffer.height)
            DispatchQueue.main.async { [weak self] in
                self?.onFrame?(image, size)
            }
        }
        try await requestFramebufferUpdate(incremental: true)
    }

    private func discardColorMap() async throws {
        let header = try await receiveExactly(5)
        let colorCount = Int(try header.uint16BE(at: 3))
        _ = try await receiveExactly(colorCount * 6)
    }

    private func publish(_ status: RFBConnectionStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(status)
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}
