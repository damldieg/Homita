import XCTest
@testable import ControlKit

/// Causa de fallo (E0-05, d): sin conexión, 5xx, 401 y 403 se distinguen.
final class APIFailureCauseTests: XCTestCase {
    func testNetworkIsOffline() {
        XCTAssertEqual(APIError.network("timed out").cause, .offline)
        XCTAssertTrue(APIError.network("timed out").isRetryable)
    }

    func testServerErrorsAreRetryable() {
        XCTAssertEqual(APIError.http(status: 500, message: "boom").cause, .server)
        XCTAssertEqual(APIError.http(status: 503, message: "down").cause, .server)
        XCTAssertTrue(APIError.http(status: 503, message: "down").isRetryable)
    }

    func testUnauthorizedAndSessionExpiredAreNotRetryable() {
        XCTAssertEqual(APIError.http(status: 401, message: "Unauthorized").cause, .unauthorized)
        XCTAssertEqual(APIError.sessionExpired.cause, .unauthorized)
        XCTAssertFalse(APIError.sessionExpired.isRetryable)
    }

    func testForbiddenKeepsServerMessageAndIsNotRetryable() {
        let error = APIError.http(status: 403, message: "Not Allowed")
        XCTAssertEqual(error.cause, .forbidden)
        XCTAssertFalse(error.isRetryable)
        XCTAssertEqual(error.userMessage, "Solo el propietario puede realizar esta acción")
    }

    func testValidationAndDecodingAreOther() {
        XCTAssertEqual(APIError.http(status: 400, message: "Invalid member").cause, .other)
        XCTAssertEqual(APIError.decoding("bad json").cause, .other)
        XCTAssertFalse(APIError.decoding("bad json").isRetryable)
    }
}
