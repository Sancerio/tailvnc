import XCTest
@testable import TailVNC

final class DESTests: XCTestCase {
    func testNISTKnownAnswerVector() {
        let encrypted = DES.encrypt(
            block: 0x0123_4567_89ab_cdef,
            key: 0x1334_5779_9bbc_dff1
        )
        XCTAssertEqual(encrypted, 0x85e8_1354_0f0a_b405)
    }

    func testVNCChallengeLengthValidation() {
        XCTAssertThrowsError(
            try VNCAuthentication.response(challenge: Data(repeating: 0, count: 15), password: "test")
        )
    }

    func testVNCResponseIsDeterministicAndBlockSized() throws {
        let challenge = Data((0..<16).map(UInt8.init))
        let first = try VNCAuthentication.response(challenge: challenge, password: "password")
        let second = try VNCAuthentication.response(challenge: challenge, password: "password")

        XCTAssertEqual(first.count, 16)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, challenge)
    }
}
