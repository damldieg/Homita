import XCTest
@testable import ControlKit

final class MemberValidationTests: XCTestCase {
    func testName() {
        XCTAssertNotNil(MemberValidation.validate(name: "", color: "#000000"))
        XCTAssertNotNil(MemberValidation.validate(name: "   ", color: "#000000"))
        XCTAssertNil(MemberValidation.validate(name: String(repeating: "a", count: 50), color: "#000000"))
        XCTAssertNotNil(MemberValidation.validate(name: String(repeating: "a", count: 51), color: "#000000"))
        XCTAssertNil(MemberValidation.validate(name: " " + String(repeating: "a", count: 50) + " ", color: "#000000"))
        XCTAssertEqual(MemberValidation.trimmedName("  Ana "), "Ana")
    }

    func testCodepointsNotUTF16() {
        XCTAssertNil(MemberValidation.validate(name: String(repeating: "😀", count: 50), color: "#000000"))
        XCTAssertNotNil(MemberValidation.validate(name: String(repeating: "😀", count: 51), color: "#000000"))
    }

    func testColor() {
        XCTAssertNil(MemberValidation.validate(name: "A", color: "#abcdef"))
        XCTAssertNil(MemberValidation.validate(name: "A", color: "#ABCDEF"))
        XCTAssertNotNil(MemberValidation.validate(name: "A", color: "abcdef"))
        XCTAssertNotNil(MemberValidation.validate(name: "A", color: "#abcde"))
        XCTAssertNotNil(MemberValidation.validate(name: "A", color: "#abcdeg"))
        XCTAssertEqual(MemberValidation.defaultColor, "#6923E2")
    }
}
