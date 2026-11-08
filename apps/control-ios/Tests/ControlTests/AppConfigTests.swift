import XCTest
@testable import ControlKit

/// `AppConfig`: validación fail-fast de la config inyectada desde `Config.xcconfig`
/// (sin placeholders, https u http solo en loopback).
final class AppConfigTests: XCTestCase {
    private func values(
        base: String = "https://proj.supabase.co/functions/v1/api",
        supabase: String = "https://proj.supabase.co",
        anonKey: String = "anon-key-test"
    ) -> [String: String] {
        [
            AppConfig.planifyBaseURLKey: base,
            AppConfig.supabaseURLKey: supabase,
            AppConfig.supabaseAnonKeyKey: anonKey
        ]
    }

    func testValidHTTPSConfig() throws {
        let config = try AppConfig(values: values())
        XCTAssertEqual(config.planifyBaseURL.absoluteString, "https://proj.supabase.co/functions/v1/api")
        XCTAssertEqual(config.supabaseURL.absoluteString, "https://proj.supabase.co")
        XCTAssertEqual(config.supabaseAnonKey, "anon-key-test")
    }

    func testLoopbackHTTPAllowedForLocalDebug() throws {
        let config = try AppConfig(values: values(base: "http://127.0.0.1:54321/functions/v1/api", supabase: "http://127.0.0.1:54321"))
        XCTAssertEqual(config.planifyBaseURL.host, "127.0.0.1")
    }

    func testMissingKeysFail() {
        XCTAssertThrowsError(try AppConfig(values: [:])) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .missing(AppConfig.planifyBaseURLKey))
        }
        XCTAssertThrowsError(try AppConfig(values: values(anonKey: "  "))) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .missing(AppConfig.supabaseAnonKeyKey))
        }
        XCTAssertThrowsError(try AppConfig(values: values(supabase: ""))) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .missing(AppConfig.supabaseURLKey))
        }
    }

    func testPlaceholdersFail() {
        // Lo que deja Config.xcconfig.example sin regenerar.
        XCTAssertThrowsError(try AppConfig(values: values(base: "https://<ref>.supabase.co/functions/v1/api"))) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .placeholder(AppConfig.planifyBaseURLKey))
        }
        XCTAssertThrowsError(try AppConfig(values: values(anonKey: "<anon key>"))) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .placeholder(AppConfig.supabaseAnonKeyKey))
        }
    }

    func testNonLoopbackHTTPFails() {
        XCTAssertThrowsError(try AppConfig(values: values(base: "http://10.0.2.2:3000/functions/v1/api"))) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .insecureURL(AppConfig.planifyBaseURLKey))
        }
    }

    func testInvalidURLFails() {
        XCTAssertThrowsError(try AppConfig(values: values(supabase: "ftp://proj.supabase.co"))) { error in
            XCTAssertEqual(error as? AppConfig.ConfigError, .invalidURL(AppConfig.supabaseURLKey))
        }
    }
}
