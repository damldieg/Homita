import XCTest
@testable import ControlKit

/// `TokenStore` (Keychain en la app) y `SessionStore`: persistencia de sesión sin UserDefaults.
final class TokenStoreTests: XCTestCase {
    func testInMemoryStoreRoundTrip() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(try store.get("access_token"))
        try store.set("valor", forKey: "access_token")
        XCTAssertEqual(try store.get("access_token"), "valor")
        try store.set("valor-2", forKey: "access_token")
        XCTAssertEqual(try store.get("access_token"), "valor-2")
        try store.remove("access_token")
        XCTAssertNil(try store.get("access_token"))
        // Borrar una clave inexistente no falla.
        try store.remove("access_token")
    }

    func testSessionRestoreRoundTrip() throws {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        XCTAssertNil(session.session)

        let user = try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#)
        session.saveSession(user: user, accessToken: "jwt-access", refreshToken: "rt-1")

        let restored = SessionStore(store: tokens)
        restored.restore()
        XCTAssertEqual(restored.session, UserSession(id: 1, name: "Demo", email: "demo@homita.example"))
        XCTAssertEqual(restored.accessToken, "jwt-access")
        XCTAssertEqual(restored.refreshToken, "rt-1")
    }

    func testRestoreWithoutTokenHasNoSession() throws {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        let user = try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#)
        session.saveSession(user: user, accessToken: "jwt-access", refreshToken: "rt-1")
        try tokens.remove("access_token")

        let restored = SessionStore(store: tokens)
        restored.restore()
        XCTAssertNil(restored.session)
    }

    func testUpdateTokensRotates() throws {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        let user = try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#)
        session.saveSession(user: user, accessToken: "jwt-access", refreshToken: "rt-1")
        session.updateTokens(access: "nuevo-access", refresh: "nuevo-refresh")

        let restored = SessionStore(store: tokens)
        restored.restore()
        XCTAssertEqual(restored.accessToken, "nuevo-access")
        XCTAssertEqual(restored.refreshToken, "nuevo-refresh")
    }

    func testSignOutClearsEverything() throws {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        let user = try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#)
        session.saveSession(user: user, accessToken: "jwt-access", refreshToken: "rt-1")
        session.signOut()

        XCTAssertNil(session.session)
        XCTAssertNil(session.accessToken)
        XCTAssertNil(session.refreshToken)
        let restored = SessionStore(store: tokens)
        restored.restore()
        XCTAssertNil(restored.session)
        // El hogar activo (store propio, mismo TokenStore) no queda tras el cierre de sesión.
        XCTAssertNil(try tokens.get("active_home_id"))
    }

    func testKeychainStoreSaveLoadDelete() throws {
        // Guarda→carga→borra en el Keychain real del host/simulador. Si el entorno no permite
        // Keychain (p. ej. sandbox de test), se salta en vez de fallar.
        let store = KeychainTokenStore(service: "com.lito.planify.control.ios.tests")
        defer { try? store.remove("test-key") }
        do {
            try store.set("valor-secreto", forKey: "test-key")
        } catch {
            throw XCTSkip("Keychain no disponible en este entorno: \(error)")
        }
        XCTAssertEqual(try store.get("test-key"), "valor-secreto")
        try store.remove("test-key")
        XCTAssertNil(try store.get("test-key"))
    }
}
