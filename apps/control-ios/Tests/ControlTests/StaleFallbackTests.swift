import XCTest
@testable import ControlKit

/// Stale-if-error (E0-06): con copia, un 5xx devuelve la copia y marca los datos como obsoletos.
final class StaleFallbackTests: XCTestCase {
    private func makeClient(cache: ReadCache) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { "7" },
            readCache: cache
        )
    }

    func testServerErrorServesCopyAndMarksStale() async throws {
        let cache = ReadCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID().uuidString)"))
        let client = makeClient(cache: cache)
        StubURLProtocol.reset { _ in .init(json: "[{\"id\":1}]") }
        _ = try await client.send(APIRequest(method: .get, path: "event/index"))

        StubURLProtocol.reset { _ in .init(status: 503, json: "{\"error\":\"down\"}") }
        let data = try await client.send(APIRequest(method: .get, path: "event/index"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[{\"id\":1}]")
        let stale = await MainActor.run { DataFreshness.shared.staleSince }
        XCTAssertNotNil(stale)
    }

    func testServerErrorWithoutCopyThrows() async {
        let cache = ReadCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString)"))
        let client = makeClient(cache: cache)
        StubURLProtocol.reset { _ in .init(status: 503, json: "{\"error\":\"down\"}") }
        do {
            _ = try await client.send(APIRequest(method: .get, path: "task/index"))
            XCTFail("sin copia debe lanzar el error")
        } catch {
            XCTAssertEqual(error as? APIError, .http(status: 503, message: "down"))
        }
    }
}
