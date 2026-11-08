import Foundation
@testable import ControlKit

/// `URLProtocol` stub para los tests de red: captura las peticiones (`URLRequest` tal cual las
/// ve URLSession) y responde con fixtures del contrato, con delay opcional para probar la
/// serialización de refrescos. Nunca toca la red real.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        var status: Int
        var body: Data
        var delay: TimeInterval

        init(status: Int = 200, json: String = "{}", delay: TimeInterval = 0) {
            self.status = status
            self.body = Data(json.utf8)
            self.delay = delay
        }
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Stub)?
    private static var captured: [URLRequest] = []

    /// Fija el handler de respuesta y limpia las peticiones capturadas.
    static func reset(_ handler: @escaping (URLRequest) -> Stub) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        captured = []
    }

    /// Peticiones capturadas en orden.
    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    /// `URLSession` de test que enruta todo por este stub.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        Self.lock.lock()
        Self.captured.append(request)
        let stub = Self.handler?(request) ?? Stub(status: 500, json: #"{"error":"Not Found"}"#)
        Self.lock.unlock()
        let respond: @Sendable () -> Void = { [weak self] in
            guard let self, let client = self.client, let url = request.url else { return }
            let response = HTTPURLResponse(
                url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: stub.body)
            client.urlProtocolDidFinishLoading(self)
        }
        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers de test

extension URLRequest {
    /// Body capturado (URLSession puede pasarlo como `httpBodyStream` al `URLProtocol`).
    var capturedBody: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// Query como pares (decodificados) para comparar el shape sin depender del percent-encoding.
    var capturedQuery: [(String, String?)] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return []
        }
        return items.map { ($0.name, $0.value) }
    }
}

/// Cliente API de prueba sobre el stub: base URL fija y token opcional (literal `test-access`).
func makeTestClient(token: String? = "test-access", refresher: (any TokenRefreshing)? = nil) -> APIClient {
    let client = APIClient(
        baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
        session: StubURLProtocol.session(),
        tokenProvider: { token }
    )
    client.refresher = refresher
    return client
}

/// `AppConfig` de prueba (sin secretos reales).
func makeTestConfig(
    base: String = "https://test.supabase.co/functions/v1/api",
    supabase: String = "https://test.supabase.co",
    anonKey: String = "anon-key-test"
) throws -> AppConfig {
    try AppConfig(values: [
        AppConfig.planifyBaseURLKey: base,
        AppConfig.supabaseURLKey: supabase,
        AppConfig.supabaseAnonKeyKey: anonKey
    ])
}

/// Decodifica un modelo desde un fixture JSON de test.
func decodeFixture<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

// MARK: - Fixtures de respuesta del contrato (shapes mínimos decodificables)

/// Responde a cualquier ruta del contrato con el shape que corresponde según método y path
/// (`supabase/migrations/0005_read_rpcs.sql` y `supabase/functions/api/usecases/*.ts`). Un path desconocido responde 500
/// `Not Found` para que el test falle si aparece una ruta inesperada.
enum ContractFixtures {
    static let user = #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#
    static let calendar = ##"{"id":3,"name":"Familia","color":"#6923E2"}"##
    static let person = ##"{"id":1,"user_id":1,"name":"Ana","color":"#FF0000"}"##
    static let event = #"{"id":5,"calendar_id":3,"title":"Reunión","date_at":"2026-11-08 09:30:00"}"#
    static let routine = #"{"id":4,"calendar_id":3,"title":"Rutina","time":"09:00","start_date":"2026-11-02"}"#
    static let taskList = ##"{"id":2,"name":"Compra","color":"#6923E2","sort":"custom"}"##
    static let task = #"{"id":7,"task_list_id":2,"title":"Leche"}"#
    // `GET task-list/user` manda `tlu_id` (no `cu_id`) como clave de la fila (0005_read_rpcs.sql).
    static let taskListUsers = #"[{"tlu_id":10,"user_id":1,"name":"Demo","email":"demo@homita.example","role":"owner"},{"tlu_id":11,"user_id":9,"name":"Invitado","email":"invitado@homita.example","role":"viewer"}]"#
    static let ok = #"{"success":true}"#
    static let config = #"{"allow_registration":false}"#
    static let goTrue = #"{"access_token":"nuevo-access","refresh_token":"nuevo-refresh"}"#

    static func response(for request: URLRequest) -> StubURLProtocol.Stub {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        // Ruta relativa al contrato (tras `/functions/v1/api/`); GoTrue va por `/auth/v1/…`.
        let route: String
        if let range = path.range(of: "/functions/v1/api/") {
            route = String(path[range.upperBound...])
        } else {
            route = path
        }
        let json: String
        switch (method, route) {
        case (_, "config"):
            json = config
        case (_, "user/auth"), (_, "user/create"), (_, "user/update"):
            json = user
        case (_, let r) where r.hasSuffix("auth/v1/token"):
            json = goTrue
        case ("GET", "calendar"):
            json = "[]"
        case (_, "calendar/detail"), (_, "calendar/create"), (_, "calendar/update"):
            json = calendar
        case (_, "calendar/delete"):
            json = ok
        case ("GET", "calendar/user"):
            json = "[]"
        case ("POST", "calendar/user"):
            json = user
        case (_, "calendar/user"):
            json = #"{"status":"ok"}"#
        case ("GET", "person"):
            json = "[]"
        case (_, "person/create"), (_, "person/update"):
            json = person
        case (_, "person/delete"):
            json = ok
        case ("GET", "routine"):
            json = "[]"
        case (_, "routine/detail"), (_, "routine/create"), (_, "routine/update"), (_, "routine/alarm"):
            json = routine
        case (_, "routine/delete"):
            json = ok
        case ("GET", "event"):
            json = "[]"
        case (_, "event/detail"), (_, "event/create"), (_, "event/update"), (_, "event/alarm"):
            json = event
        case (_, "event/delete"):
            json = ok
        case ("GET", "task-list"):
            json = "[]"
        case (_, "task-list/detail"), (_, "task-list/create"), (_, "task-list/update"):
            json = taskList
        case (_, "task-list/delete"):
            json = ok
        case ("GET", "task-list/user"):
            json = taskListUsers
        case ("POST", "task-list/user"):
            json = user
        case (_, "task-list/user"):
            json = #"{"status":"ok"}"#
        case ("GET", "task"):
            json = "[]"
        case (_, "task/detail"), (_, "task/create"), (_, "task/update"), (_, "task/complete"), (_, "task/order"):
            json = task
        case (_, "task/delete"):
            json = ok
        default:
            return StubURLProtocol.Stub(status: 500, json: #"{"error":"Not Found"}"#)
        }
        return StubURLProtocol.Stub(json: json)
    }
}
