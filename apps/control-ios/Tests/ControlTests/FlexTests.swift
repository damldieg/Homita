import XCTest
@testable import ControlKit

/// `FlexBool`/`FlexInt`: formas tolerantes del contrato (0/1 int, "0"/"1", bool JSON).
final class FlexTests: XCTestCase {
    private struct BoolBox: Decodable { let v: FlexBool? }
    private struct RequiredBoolBox: Decodable { let v: FlexBool }
    private struct IntBox: Decodable { let v: FlexInt }

    private func decodeBool(_ json: String) throws -> Bool {
        try decodeFixture(RequiredBoolBox.self, json).v.value
    }

    func testFlexBoolAcceptedForms() throws {
        XCTAssertEqual(try decodeBool(#"{"v":true}"#), true)
        XCTAssertEqual(try decodeBool(#"{"v":false}"#), false)
        XCTAssertEqual(try decodeBool(#"{"v":1}"#), true)
        XCTAssertEqual(try decodeBool(#"{"v":0}"#), false)
        XCTAssertEqual(try decodeBool(#"{"v":"1"}"#), true)
        XCTAssertEqual(try decodeBool(#"{"v":"0"}"#), false)
        XCTAssertEqual(try decodeBool(#"{"v":"true"}"#), true)
        XCTAssertEqual(try decodeBool(#"{"v":"false"}"#), false)
    }

    func testFlexBoolRejectsInvalidForms() {
        XCTAssertThrowsError(try decodeBool(#"{"v":2}"#))
        XCTAssertThrowsError(try decodeBool(#"{"v":-1}"#))
        XCTAssertThrowsError(try decodeBool(#"{"v":"yes"}"#))
        XCTAssertThrowsError(try decodeBool(#"{"v":"2"}"#))
        XCTAssertThrowsError(try decodeBool(#"{"v":1.5}"#))
    }

    func testFlexBoolNullIsNilWhenOptional() throws {
        let box = try decodeFixture(BoolBox.self, #"{"v":null}"#)
        XCTAssertNil(box.v)
    }

    func testFlexBoolEncodesAsBool() throws {
        let data = try JSONEncoder().encode(FlexBool(true))
        XCTAssertEqual(String(data: data, encoding: .utf8), "true")
    }

    func testFlexIntAcceptedForms() throws {
        XCTAssertEqual(try decodeFixture(IntBox.self, #"{"v":5}"#).v.value, 5)
        XCTAssertEqual(try decodeFixture(IntBox.self, #"{"v":"5"}"#).v.value, 5)
        XCTAssertEqual(try decodeFixture(IntBox.self, #"{"v":0}"#).v.value, 0)
    }

    func testFlexIntRejectsInvalidForms() {
        XCTAssertThrowsError(try decodeFixture(IntBox.self, #"{"v":"x"}"#))
        XCTAssertThrowsError(try decodeFixture(IntBox.self, #"{"v":"1.5"}"#))
        XCTAssertThrowsError(try decodeFixture(IntBox.self, #"{"v":true}"#))
    }
}
