import XCTest
@testable import ControlKit

final class AppServicesTests: XCTestCase {
    func testSignOutClearsActiveHome() async throws {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        session.saveSession(user: try decodeFixture(UserResponse.self, ContractFixtures.user), accessToken: "a", refreshToken: "r")
        let services = AppServices(config: try makeTestConfig(), session: session, tokenStore: tokens, http: StubURLProtocol.session())
        StubURLProtocol.reset(ContractFixtures.response)
        await services.homeContext.load(using: services.homes)
        XCTAssertNotNil(services.homeContext.activeHomeId)
        XCTAssertEqual(try tokens.get("active_home_id"), "2")

        services.signOut()

        for key in ["access_token", "refresh_token", "user_id", "user_name", "user_email", "active_home_id"] {
            XCTAssertNil(try tokens.get(key), key)
        }
        XCTAssertEqual(services.homeContext.state, .unresolved)
        XCTAssertNil(services.homeContext.activeHomeId)
        XCTAssertNil(session.session)
    }
}
