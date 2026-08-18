import CoreGraphics
import Foundation
import Network
import XCTest
@testable import TailVNC

final class RFBClientIntegrationTests: XCTestCase {
    func testNegotiatesVNCAuthenticationAndReceivesRawFrame() async throws {
        let server = try MockRFBServer(password: "testpass")
        let port = try await server.start()
        defer { server.stop() }

        let connected = expectation(description: "connected")
        let frameReceived = expectation(description: "frame received")
        let client = RFBClient()

        client.onStatus = { status in
            if case .connected(let name, let width, let height) = status {
                XCTAssertEqual(name, "Mock Mac")
                XCTAssertEqual(width, 2)
                XCTAssertEqual(height, 2)
                connected.fulfill()
            }
        }
        client.onFrame = { image, size in
            XCTAssertEqual(image.width, 2)
            XCTAssertEqual(image.height, 2)
            XCTAssertEqual(size, CGSize(width: 2, height: 2))
            frameReceived.fulfill()
        }

        client.connect(host: "127.0.0.1", port: port, password: "testpass")
        await fulfillment(of: [connected, frameReceived], timeout: 5)
        client.disconnect()

        try await server.waitUntilComplete()
    }
}

private final class MockRFBServer: @unchecked Sendable {
    private let password: String
    private let queue = DispatchQueue(label: "com.sancerio.tailvnc.tests.mock-rfb")
    private let listener: NWListener
    private var connection: NWConnection?
    private var serverTask: Task<Void, Never>?
    private var completion: Result<Void, Error>?
    private var completionWaiters: [CheckedContinuation<Void, Error>] = []
    private let lock = NSLock()

    init(password: String) throws {
        self.password = password
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let gate = TestContinuationGate()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard gate.claim(), let port = self.listener.port?.rawValue else { return }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connection = connection
                connection.start(queue: self.queue)
                self.serverTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.run(connection)
                        self.finish(.success(()))
                    } catch {
                        self.finish(.failure(error))
                    }
                }
            }
            listener.start(queue: queue)
        }
        return port
    }

    func stop() {
        serverTask?.cancel()
        connection?.cancel()
        listener.cancel()
    }

    func waitUntilComplete() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let completion {
                lock.unlock()
                continuation.resume(with: completion)
            } else {
                completionWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        completion = result
        let waiters = completionWaiters
        completionWaiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func run(_ connection: NWConnection) async throws {
        try await send(Data("RFB 003.889\n".utf8), over: connection)
        let clientGreeting = try await receiveExactly(12, from: connection)
        XCTAssertEqual(clientGreeting, Data("RFB 003.008\n".utf8))

        try await send(Data([1, 2]), over: connection)
        let selectedSecurityType = try await receiveExactly(1, from: connection)
        XCTAssertEqual(selectedSecurityType, Data([2]))

        let challenge = Data((0..<16).map(UInt8.init))
        try await send(challenge, over: connection)
        let response = try await receiveExactly(16, from: connection)
        XCTAssertEqual(response, try VNCAuthentication.response(challenge: challenge, password: password))

        try await send(Data([0, 0, 0, 0]), over: connection)
        let clientInit = try await receiveExactly(1, from: connection)
        XCTAssertEqual(clientInit, Data([1]))

        var serverInit = Data()
        serverInit.appendUInt16BE(2)
        serverInit.appendUInt16BE(2)
        serverInit.append(contentsOf: [32, 24, 0, 1])
        serverInit.appendUInt16BE(255)
        serverInit.appendUInt16BE(255)
        serverInit.appendUInt16BE(255)
        serverInit.append(contentsOf: [16, 8, 0, 0, 0, 0])
        let name = Data("Mock Mac".utf8)
        serverInit.appendUInt32BE(UInt32(name.count))
        serverInit.append(name)
        try await send(serverInit, over: connection)

        let setPixelFormat = try await receiveExactly(20, from: connection)
        XCTAssertEqual(setPixelFormat[0], 0)
        let setEncodings = try await receiveExactly(12, from: connection)
        XCTAssertEqual(setEncodings[0], 2)
        let initialRequest = try await receiveExactly(10, from: connection)
        XCTAssertEqual(initialRequest.prefix(2), Data([3, 0]))

        var update = Data([0, 0])
        update.appendUInt16BE(1)
        update.appendUInt16BE(0)
        update.appendUInt16BE(0)
        update.appendUInt16BE(2)
        update.appendUInt16BE(2)
        update.appendInt32BE(0)
        update.append(contentsOf: [
            0, 0, 255, 0,
            0, 255, 0, 0,
            255, 0, 0, 0,
            255, 255, 255, 0,
        ])
        try await send(update, over: connection)

        let incrementalRequest = try await receiveExactly(10, from: connection)
        XCTAssertEqual(incrementalRequest.prefix(2), Data([3, 1]))
    }

    private func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> Data {
        var data = Data()
        while data.count < count {
            let remaining = count - data.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { content, _, complete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if complete {
                        continuation.resume(throwing: MockRFBError.closed)
                    } else {
                        continuation.resume(throwing: MockRFBError.closed)
                    }
                }
            }
            data.append(chunk)
        }
        return data
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

private enum MockRFBError: Error {
    case closed
}

private final class TestContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
