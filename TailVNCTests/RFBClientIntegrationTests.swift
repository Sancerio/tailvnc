import CoreGraphics
import Foundation
import Network
import Security
import XCTest
@testable import TailVNC

final class RFBClientIntegrationTests: XCTestCase {
    func testNegotiatesVNCAuthenticationAndReceivesRawFrame() async throws {
        let server = try MockRFBServer(authentication: .vnc(password: "testpass"))
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
            client.sendPointer(x: 1, y: 1, buttonMask: 1)
            client.sendPointer(x: 1, y: 1, buttonMask: 0)
            client.sendKey(0xff0d)
            client.requestFullRefresh()
            frameReceived.fulfill()
        }

        client.connect(
            host: "127.0.0.1",
            port: port,
            authentication: .vncPassword("testpass")
        )
        await fulfillment(of: [connected, frameReceived], timeout: 5)
        try await server.waitUntilComplete()
        client.disconnect()
    }

    func testNegotiatesAppleAccountAuthenticationAndReceivesRawFrame() async throws {
        let server = try MockRFBServer(
            authentication: .apple(username: "mac-user", password: "mac-password")
        )
        let port = try await server.start()
        defer { server.stop() }

        let connected = expectation(description: "connected")
        let frameReceived = expectation(description: "frame received")
        let client = RFBClient()
        client.onStatus = { status in
            if case .connected = status { connected.fulfill() }
        }
        client.onFrame = { _, _ in
            client.sendPointer(x: 1, y: 1, buttonMask: 1)
            client.sendPointer(x: 1, y: 1, buttonMask: 0)
            client.sendKey(0xff0d)
            client.requestFullRefresh()
            frameReceived.fulfill()
        }

        client.connect(
            host: "127.0.0.1",
            port: port,
            authentication: .macAccount(username: "mac-user", password: "mac-password")
        )
        await fulfillment(of: [connected, frameReceived], timeout: 5)
        try await server.waitUntilComplete()
        client.disconnect()
    }
}

private enum MockAuthentication {
    case vnc(password: String)
    case apple(username: String, password: String)
}

private final class MockRFBServer: @unchecked Sendable {
    private let authentication: MockAuthentication
    private let applePrivateKey: SecKey?
    private let queue = DispatchQueue(label: "com.sancerio.tailvnc.tests.mock-rfb")
    private let listener: NWListener
    private var connection: NWConnection?
    private var serverTask: Task<Void, Never>?
    private var completion: Result<Void, Error>?
    private var completionWaiters: [CheckedContinuation<Void, Error>] = []
    private let lock = NSLock()

    init(authentication: MockAuthentication) throws {
        self.authentication = authentication
        if case .apple = authentication {
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 2_048
            ]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                throw error?.takeRetainedValue() ?? MockRFBError.keyGeneration
            }
            self.applePrivateKey = key
        } else {
            self.applePrivateKey = nil
        }
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
        switch authentication {
        case .vnc(let password):
            XCTAssertEqual(clientGreeting, Data("RFB 003.008\n".utf8))
            try await send(Data([1, 2]), over: connection)
            let selectedSecurityType = try await receiveExactly(1, from: connection)
            XCTAssertEqual(selectedSecurityType, Data([2]))

            let challenge = Data((0..<16).map(UInt8.init))
            try await send(challenge, over: connection)
            let response = try await receiveExactly(16, from: connection)
            XCTAssertEqual(
                response,
                try VNCAuthentication.response(challenge: challenge, password: password)
            )

        case .apple(let username, let password):
            XCTAssertEqual(clientGreeting, Data("RFB 003.889\n".utf8))
            try await send(Data([2, 2, AppleRSAAuthentication.securityType]), over: connection)
            let selectionAndRequest = try await receiveExactly(15, from: connection)
            XCTAssertEqual(selectionAndRequest.first, AppleRSAAuthentication.securityType)
            XCTAssertEqual(Data(selectionAndRequest.dropFirst()), AppleRSAAuthentication.keyRequest)
            try await performAppleHandshake(
                username: username,
                password: password,
                connection: connection
            )
        }

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

        let pointerDown = try await receiveExactly(6, from: connection)
        XCTAssertEqual(pointerDown, Data([5, 1, 0, 1, 0, 1]))
        let pointerUp = try await receiveExactly(6, from: connection)
        XCTAssertEqual(pointerUp, Data([5, 0, 0, 1, 0, 1]))

        let returnDown = try await receiveExactly(8, from: connection)
        XCTAssertEqual(returnDown, Data([4, 1, 0, 0, 0, 0, 0xff, 0x0d]))
        let returnUp = try await receiveExactly(8, from: connection)
        XCTAssertEqual(returnUp, Data([4, 0, 0, 0, 0, 0, 0xff, 0x0d]))

        let fullRefresh = try await receiveExactly(10, from: connection)
        XCTAssertEqual(fullRefresh.prefix(2), Data([3, 0]))
    }

    private func performAppleHandshake(
        username: String,
        password: String,
        connection: NWConnection
    ) async throws {
        let privateKey = try XCTUnwrap(applePrivateKey)
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        var keyError: Unmanaged<CFError>?
        let pkcs1 = try XCTUnwrap(
            SecKeyCopyExternalRepresentation(publicKey, &keyError) as Data?,
            keyError?.takeRetainedValue().localizedDescription ?? "Missing public key"
        )
        let spki = subjectPublicKeyInfo(wrapping: pkcs1)
        var keyPacket = Data([0, 1])
        keyPacket.appendUInt32BE(UInt32(spki.count))
        keyPacket.append(spki)
        keyPacket.append(0)
        var framedKeyPacket = Data()
        framedKeyPacket.appendUInt32BE(UInt32(keyPacket.count))
        framedKeyPacket.append(keyPacket)
        try await send(framedKeyPacket, over: connection)

        let responseLength = Int(try await receiveExactly(4, from: connection).uint32BE(at: 0))
        let response = try await receiveExactly(responseLength, from: connection)
        XCTAssertEqual(response[0..<8], Data([1, 0]) + Data("RSA1".utf8) + Data([0, 1]))
        XCTAssertEqual(response[136..<138], Data([0, 1]))

        let encryptedKey = Data(response[138...])
        let aesKey = try XCTUnwrap(
            SecKeyCreateDecryptedData(
                privateKey,
                .rsaEncryptionPKCS1,
                encryptedKey as CFData,
                &keyError
            ) as Data?,
            keyError?.takeRetainedValue().localizedDescription ?? "Unable to decrypt AES key"
        )
        let credentials = try AppleRSAAuthentication.decryptCredentialsForTesting(
            Data(response[8..<136]),
            aesKey: aesKey
        )
        XCTAssertEqual(nullTerminatedString(Data(credentials[0..<64])), username)
        XCTAssertEqual(nullTerminatedString(Data(credentials[64..<128])), password)

        try await send(Data(repeating: 0, count: 4), over: connection)
    }

    private func nullTerminatedString(_ data: Data) -> String {
        let content = data.prefix { $0 != 0 }
        return String(decoding: content, as: UTF8.self)
    }

    private func subjectPublicKeyInfo(wrapping pkcs1: Data) -> Data {
        let algorithm = Data([
            0x30, 0x0d,
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00
        ])
        return der(tag: 0x30, value: algorithm + der(tag: 0x03, value: Data([0]) + pkcs1))
    }

    private func der(tag: UInt8, value: Data) -> Data {
        var result = Data([tag])
        if value.count < 128 {
            result.append(UInt8(value.count))
        } else {
            let bytes = withUnsafeBytes(of: UInt32(value.count).bigEndian) { Data($0) }
                .drop(while: { $0 == 0 })
            result.append(0x80 | UInt8(bytes.count))
            result.append(contentsOf: bytes)
        }
        result.append(value)
        return result
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
    case keyGeneration
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
