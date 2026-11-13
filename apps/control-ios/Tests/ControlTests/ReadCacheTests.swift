import XCTest
@testable import ControlKit

/// Caché de lectura (E0-06): qué se guarda, con qué clave, y el fallback ante fallo del servidor.
final class ReadCacheTests: XCTestCase {
    private func tempCache() -> ReadCache {
        ReadCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("readcache-test-\(UUID().uuidString)"))
    }

    func testSaveLoadAndClear() {
        let cache = tempCache()
        let date = Date(timeIntervalSince1970: 1_000)
        cache.save(key: "k1", body: Data("{\"a\":1}".utf8), at: date)
        XCTAssertEqual(cache.load(key: "k1"), ReadCache.Entry(savedAt: date, body: Data("{\"a\":1}".utf8)))
        cache.clear()
        XCTAssertNil(cache.load(key: "k1"))
    }

    func testOnlyDataGetsAreCacheable() {
        XCTAssertTrue(ReadCache.isCacheable(APIRequest(method: .get, path: "event/index")))
        XCTAssertFalse(ReadCache.isCacheable(APIRequest(method: .post, path: "event/create")))
        XCTAssertFalse(ReadCache.isCacheable(APIRequest(method: .get, path: "home/invitation/list")))
        XCTAssertFalse(ReadCache.isCacheable(APIRequest(method: .get, path: "user/me")))
        XCTAssertFalse(ReadCache.isCacheable(APIRequest(method: .get, path: "config", isPublic: true)))
    }

    func testKeyDependsOnHomeAndQuery() {
        let request = APIRequest(method: .get, path: "event/index", query: [URLQueryItem(name: "from", value: "2026-11-12")])
        XCTAssertNotEqual(ReadCache.key(for: request, homeId: "1"), ReadCache.key(for: request, homeId: "2"))
        XCTAssertEqual(ReadCache.key(for: request, homeId: "1"), ReadCache.key(for: request, homeId: "1"))
    }
}
