import XCTest
@testable import ControlKit

/// Fallos de escritura (E0-05, c): toast con «Reintentar» en vez de la alerta «Aviso/OK». Las
/// lecturas siguen en `errorMessage`; las escrituras van a `writeFailure` con la acción para repetirla.
final class WriteFailureTests: XCTestCase {
    private func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private func makeTasksStore(_ handler: @escaping (URLRequest) -> StubURLProtocol.Stub) -> TasksStore {
        StubURLProtocol.reset(handler)
        let client = makeTestClient()
        return TasksStore(taskLists: TaskListRepository(client: client), tasks: TaskRepository(client: client))
    }

    /// Respuestas del contrato salvo `task/create`, que responde `createStatus` (mutable entre llamadas).
    private final class CreateResponder: @unchecked Sendable {
        var createStatus = 500
    }

    // MARK: - Mapeo de error a toast

    func testRetryOnlyForNetworkAndServerErrors() {
        let retry: () async -> Bool = { true }
        XCTAssertNotNil(WriteFailure(error: APIError.network("offline"), retry: retry).retry)
        XCTAssertNotNil(WriteFailure(error: APIError.http(status: 503, message: "boom"), retry: retry).retry)
        XCTAssertNil(WriteFailure(error: APIError.http(status: 422, message: "Title is required"), retry: retry).retry)
        XCTAssertNil(WriteFailure(error: APIError.http(status: 403, message: "Not Allowed"), retry: retry).retry)
        XCTAssertNil(WriteFailure(error: APIError.sessionExpired, retry: retry).retry)
        XCTAssertNil(WriteFailure(error: URLError(.badURL), retry: retry).retry)
    }

    func testMessageIsServerUserMessage() {
        // 403 `Not Allowed` en una escritura = falta de permiso de edición (0029): mensaje claro.
        let failure = WriteFailure(error: APIError.http(status: 403, message: "Not Allowed")) { true }
        XCTAssertEqual(failure.message,
                       "No tienes permiso para hacer este cambio. Pide al propietario que te dé permiso de edición.")
        XCTAssertEqual(WriteFailure(error: APIError.network("x")) { true }.message, "Error de conexión. Comprueba la red.")
    }

    // MARK: - Store: recuerda la escritura fallida y la reintenta

    func testFailedCreateRecordsRetryableFailureAndRetryRepeatsTheWrite() async {
        let responder = CreateResponder()
        let store = makeTasksStore { request in
            if self.route(request) == "task/create" {
                return responder.createStatus == 200
                    ? StubURLProtocol.Stub(json: ContractFixtures.task)
                    : StubURLProtocol.Stub(status: responder.createStatus, json: #"{"error":"boom"}"#)
            }
            return ContractFixtures.response(for: request)
        }

        let ok = await store.createTask(title: "Leche nueva", listId: 2)
        XCTAssertFalse(ok)
        XCTAssertNil(store.errorMessage, "una escritura no usa la alerta de lectura")
        let failure = try? XCTUnwrap(store.writeFailure)
        XCTAssertEqual(failure?.message, "boom")
        let retry = try? XCTUnwrap(failure?.retry)

        responder.createStatus = 200
        let retried = await retry?()
        XCTAssertEqual(retried, true)
        let creates = StubURLProtocol.requests.filter { route($0) == "task/create" }
        XCTAssertEqual(creates.count, 2, "el reintento repite la misma escritura")
        XCTAssertEqual(creates.last?.httpMethod, "POST")
        XCTAssertEqual(StubURLProtocol.requests.last.map(route), "task", "tras el reintento correcto recarga")
    }

    func testRetryThatFailsAgainRecordsANewFailure() async {
        let store = makeTasksStore { request in
            self.route(request) == "task/create"
                ? StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#)
                : ContractFixtures.response(for: request)
        }
        await store.createTask(title: "Leche nueva", listId: 2)
        let first = store.writeFailure
        store.writeFailure = nil // el toast se cierra al pulsar «Reintentar»
        let retried = await first?.retry?()
        XCTAssertEqual(retried, false)
        XCTAssertNotNil(store.writeFailure)
        XCTAssertNotEqual(store.writeFailure?.id, first?.id)
        XCTAssertNotNil(store.writeFailure?.retry)
    }

    func testValidationErrorHasNoRetry() async {
        let store = makeTasksStore { request in
            self.route(request) == "task/update"
                ? StubURLProtocol.Stub(status: 422, json: #"{"error":"Title is required"}"#)
                : ContractFixtures.response(for: request)
        }
        let task = try! decodeFixture(TaskEntry.self, ContractFixtures.task)
        let ok = await store.updateTask(task, title: "x")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.writeFailure?.message, "Title is required")
        XCTAssertNil(store.writeFailure?.retry)
    }

    func testDuplicateTitleIsRejectedWithoutRequestOrRetry() async throws {
        let store = makeTasksStore { request in
            self.route(request) == "task"
                ? StubURLProtocol.Stub(json: "[\(ContractFixtures.task)]")
                : ContractFixtures.response(for: request)
        }
        await store.loadTasks()
        let existing = try XCTUnwrap(store.tasks.first)
        let before = StubURLProtocol.requests.count
        let ok = await store.createTask(title: " \(existing.title.uppercased()) ", listId: existing.task_list_id)
        XCTAssertFalse(ok)
        XCTAssertEqual(StubURLProtocol.requests.count, before, "no se envía nada")
        XCTAssertEqual(store.writeFailure?.message, "Ya existe una tarea con ese título en la lista")
        XCTAssertNil(store.writeFailure?.retry)
    }

    /// El editor de tarea se cierra solo si la escritura fue bien (T11): el resultado lo da el store.
    func testTaskWritesReportSuccessForTheEditor() async throws {
        let store = makeTasksStore(ContractFixtures.response)
        let task = try decodeFixture(TaskEntry.self, ContractFixtures.task)
        let updated = await store.updateTask(task, title: "Leche entera")
        let created = await store.createTask(title: "Pan", listId: 2)
        XCTAssertTrue(updated)
        XCTAssertTrue(created)
        XCTAssertNil(store.writeFailure)
    }

    func testReadFailureStaysInErrorMessage() async {
        let store = makeTasksStore { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
        await store.loadTasks()
        XCTAssertEqual(store.errorMessage, "boom")
        XCTAssertNil(store.writeFailure)
    }

    func testRetryDoesNotRetainTheStore() async {
        var store: TasksStore? = makeTasksStore { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
        await store?.deleteTask(try! decodeFixture(TaskEntry.self, ContractFixtures.task))
        let retry = store?.writeFailure?.retry
        XCTAssertNotNil(retry)
        weak var weakStore = store
        store = nil
        XCTAssertNil(weakStore, "el reintento guardado no debe retener el store")
        let retried = await retry?()
        XCTAssertEqual(retried, false)
    }

    func testOtherStoresReportWritesToTheToast() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
        let client = makeTestClient()

        let persons = PersonStore(repo: PersonRepository(client: client))
        let savedPerson = await persons.save(name: "Ana", color: "#112233", editing: nil)
        XCTAssertFalse(savedPerson)
        XCTAssertNotNil(persons.writeFailure?.retry)

        let calendars = CalendarStore(repo: CalendarRepository(client: client))
        let savedCalendar = await calendars.save(name: "Casa", color: "#112233", widget: false, dashboard: false, editing: nil)
        XCTAssertFalse(savedCalendar)
        XCTAssertNotNil(calendars.writeFailure?.retry)

        let inicio = InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client)
        )
        let created = await inicio.createTask(title: "Leche", listId: 2)
        XCTAssertFalse(created)
        XCTAssertNotNil(inicio.writeFailure?.retry)
        XCTAssertNil(inicio.errorMessage)

        XCTAssertNil(persons.errorMessage)
        XCTAssertNil(calendars.errorMessage)
    }
}
