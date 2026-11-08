import XCTest
@testable import ControlKit

/// Forma de petición por repo (método, path, query y body exactos) contra los shapes del
/// inventario de contrato (local, no versionado; ver `supabase/functions/api/usecases/*.ts`). Los bodies se
/// comparan como JSON con claves ordenadas (determinista).
final class RequestShapeTests: XCTestCase {
    private func setUpStub() {
        StubURLProtocol.reset(ContractFixtures.response)
    }

    private func sent() throws -> URLRequest {
        try XCTUnwrap(StubURLProtocol.requests.last)
    }

    private func assertShape(
        _ request: URLRequest, method: String, path: String,
        query: [(String, String?)] = [], body: String? = nil,
        bearer: String? = "Bearer test-access",
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(request.httpMethod, method, file: file, line: line)
        XCTAssertEqual(request.url?.path.hasSuffix(path), true, "path \(path)", file: file, line: line)
        XCTAssertEqual(request.capturedQuery.map(\.0), query.map(\.0), file: file, line: line)
        XCTAssertEqual(
            request.capturedQuery.map { $0.1 ?? "" }, query.map { $0.1 ?? "" },
            file: file, line: line
        )
        if let body {
            XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8), body, file: file, line: line)
        } else {
            XCTAssertNil(request.capturedBody, file: file, line: line)
        }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), bearer, file: file, line: line)
    }

    // MARK: - Usuario

    func testUserShapes() async throws {
        setUpStub()
        let client = makeTestClient()

        _ = try await client.send(APIRequest(method: .get, path: "config", isPublic: true), as: ConfigResponse.self)
        try assertShape(sent(), method: "GET", path: "/config", body: nil, bearer: nil)

        let authBody = try client.encode(AuthRequest(email: "demo@homita.example", password: "demo1234"))
        _ = try await client.send(APIRequest(method: .post, path: "user/auth", body: authBody, isPublic: true), as: UserResponse.self)
        try assertShape(sent(), method: "POST", path: "/user/auth", body: #"{"email":"demo@homita.example","password":"demo1234"}"#, bearer: nil)

        let registerBody = try client.encode(RegisterRequest(name: "Demo", email: "demo@homita.example", password: "demo1234"))
        _ = try await client.send(APIRequest(method: .post, path: "user/create", body: registerBody, isPublic: true), as: UserResponse.self)
        try assertShape(sent(), method: "POST", path: "/user/create", body: #"{"email":"demo@homita.example","name":"Demo","password":"demo1234"}"#, bearer: nil)

        let updateBody = try client.encode(UpdateProfileRequest(name: "Demo", email: "demo@homita.example", password: nil))
        _ = try await client.send(APIRequest(method: .patch, path: "user/update", body: updateBody), as: UserResponse.self)
        try assertShape(sent(), method: "PATCH", path: "/user/update", body: #"{"email":"demo@homita.example","name":"Demo"}"#)
    }

    // MARK: - Calendarios

    func testCalendarShapes() async throws {
        setUpStub()
        let client = makeTestClient()
        let repo = CalendarRepository(client: client)

        _ = try await repo.index()
        try assertShape(sent(), method: "GET", path: "/calendar", body: nil)

        _ = try await repo.detail(id: 3)
        try assertShape(sent(), method: "GET", path: "/calendar/detail", query: [("id", "3")], body: nil)

        _ = try await repo.create(CreateCalendarRequest(name: "Familia", color: "#6923E2", widget: true, dashboard: true))
        try assertShape(sent(), method: "POST", path: "/calendar/create",
                        body: ##"{"color":"#6923E2","dashboard":true,"name":"Familia","widget":true}"##)

        _ = try await repo.update(UpdateCalendarRequest(id: 3, name: "Familia", color: "#6923E2", widget: true, dashboard: false))
        try assertShape(sent(), method: "PATCH", path: "/calendar/update",
                        body: ##"{"color":"#6923E2","dashboard":false,"id":3,"name":"Familia","widget":true}"##)

        try await repo.delete(id: 3)
        try assertShape(sent(), method: "DELETE", path: "/calendar/delete", body: #"{"id":3}"#)

        _ = try await repo.users(calendarId: 3)
        try assertShape(sent(), method: "GET", path: "/calendar/user", query: [("calendar_id", "3")], body: nil)

        _ = try await repo.invite(calendarId: 3, email: "invitado@homita.example")
        try assertShape(sent(), method: "POST", path: "/calendar/user",
                        body: #"{"calendar_id":3,"email":"invitado@homita.example"}"#)

        try await repo.removeUser(calendarId: 3, userId: 9)
        try assertShape(sent(), method: "DELETE", path: "/calendar/user",
                        body: #"{"calendar_id":3,"user_id":9}"#)
    }

    // MARK: - Eventos

    func testEventShapes() async throws {
        setUpStub()
        let client = makeTestClient()
        let repo = EventRepository(client: client)
        let timezone = "Europe/Madrid"

        _ = try await repo.index()
        try assertShape(sent(), method: "GET", path: "/event", body: nil)

        // Filtros SIEMPRE en query (`search`, nunca `q`; epoch de 10 dígitos en start_date).
        var filters = EventFilters(calendarId: 3, search: "reunión", startDate: "1762586400", timezone: timezone)
        filters.endDate = "1762672800"
        filters.orderMode = "DESC"
        filters.routine = true
        _ = try await repo.index(filters)
        try assertShape(
            sent(), method: "GET", path: "/event",
            query: [
                ("calendar_id", "3"), ("search", "reunión"), ("start_date", "1762586400"),
                ("end_date", "1762672800"), ("order_mode", "DESC"), ("routine", "true"),
                ("timezone", "Europe/Madrid")
            ],
            body: nil
        )

        _ = try await repo.detail(id: 5, timezone: timezone)
        try assertShape(sent(), method: "GET", path: "/event/detail",
                        query: [("id", "5"), ("timezone", "Europe/Madrid")], body: nil)

        _ = try await repo.create(CreateEventRequest(
            calendar_id: 3, title: "Reunión", date_at: "2026-11-08 09:30:00", alarm: 10, person_ids: [1, 2]
        ))
        try assertShape(sent(), method: "POST", path: "/event/create",
                        body: #"{"alarm":10,"calendar_id":3,"date_at":"2026-11-08 09:30:00","person_ids":[1,2],"title":"Reunión"}"#)

        _ = try await repo.update(UpdateEventRequest(
            id: 5, title: "Reunión", date_at: "2026-11-08 10:00:00", alarm: nil, person_ids: []
        ), timezone: timezone)
        // `alarm` nil se omite (como Gson): sin aviso lo fija el servidor por defecto.
        try assertShape(sent(), method: "PATCH", path: "/event/update",
                        query: [("timezone", "Europe/Madrid")],
                        body: #"{"date_at":"2026-11-08 10:00:00","id":5,"person_ids":[],"title":"Reunión"}"#)

        _ = try await repo.setAlarm(SetEventAlarmRequest(event_id: 5, alarm: 30), timezone: timezone)
        try assertShape(sent(), method: "PATCH", path: "/event/alarm",
                        query: [("timezone", "Europe/Madrid")], body: #"{"alarm":30,"event_id":5}"#)

        try await repo.delete(id: 5, timezone: timezone)
        try assertShape(sent(), method: "DELETE", path: "/event/delete",
                        query: [("timezone", "Europe/Madrid")], body: #"{"id":5}"#)
    }

    // MARK: - Rutinas

    func testRoutineShapes() async throws {
        setUpStub()
        let client = makeTestClient()
        let repo = RoutineRepository(client: client)
        let timezone = "Europe/Madrid"

        _ = try await repo.index(timezone: timezone)
        try assertShape(sent(), method: "GET", path: "/routine",
                        query: [("timezone", "Europe/Madrid")], body: nil)

        _ = try await repo.detail(id: 4, timezone: timezone)
        try assertShape(sent(), method: "GET", path: "/routine/detail",
                        query: [("id", "4"), ("timezone", "Europe/Madrid")], body: nil)

        _ = try await repo.create(CreateRoutineRequest(
            calendar_id: 3, title: "Rutina", frequency: "weekly", interval: 2, days: [1, 5],
            time: "09:00", start_date: "2026-11-02", end_date: nil, active: true, alarm: 10, person_ids: [1]
        ), timezone: timezone)
        // `end_date` nil se omite; `alarm` va en create (misma semántica que Android).
        try assertShape(sent(), method: "POST", path: "/routine/create",
                        query: [("timezone", "Europe/Madrid")],
                        body: #"{"active":true,"alarm":10,"calendar_id":3,"days":[1,5],"frequency":"weekly","interval":2,"person_ids":[1],"start_date":"2026-11-02","time":"09:00","title":"Rutina"}"#)

        _ = try await repo.update(UpdateRoutineRequest(
            id: 4, title: "Rutina", frequency: "weekly", interval: 2, days: [1, 5],
            time: "09:00", start_date: "2026-11-02", end_date: "2027-11-02", active: false, person_ids: [1]
        ), timezone: timezone)
        // `PATCH routine/update` SIN `alarm` (se cambia aparte).
        try assertShape(sent(), method: "PATCH", path: "/routine/update",
                        query: [("timezone", "Europe/Madrid")],
                        body: #"{"active":false,"days":[1,5],"end_date":"2027-11-02","frequency":"weekly","id":4,"interval":2,"person_ids":[1],"start_date":"2026-11-02","time":"09:00","title":"Rutina"}"#)

        _ = try await repo.setAlarm(SetRoutineAlarmRequest(id: 4, alarm: nil), timezone: timezone)
        try assertShape(sent(), method: "PATCH", path: "/routine/alarm",
                        query: [("timezone", "Europe/Madrid")], body: #"{"id":4}"#)

        try await repo.delete(id: 4, timezone: timezone)
        try assertShape(sent(), method: "DELETE", path: "/routine/delete",
                        query: [("timezone", "Europe/Madrid")], body: #"{"id":4}"#)
    }

    // MARK: - Listas de tareas y tareas

    func testTaskListShapes() async throws {
        setUpStub()
        let client = makeTestClient()
        let repo = TaskListRepository(client: client)

        _ = try await repo.index()
        try assertShape(sent(), method: "GET", path: "/task-list", body: nil)

        _ = try await repo.detail(id: 2)
        try assertShape(sent(), method: "GET", path: "/task-list/detail", query: [("id", "2")], body: nil)

        _ = try await repo.create(CreateTaskListRequest(name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: true))
        try assertShape(sent(), method: "POST", path: "/task-list/create",
                        body: ##"{"color":"#6923E2","dashboard":true,"name":"Compra","sort":"custom","widget":true}"##)

        _ = try await repo.create(CreateTaskListRequest(name: "Compra", color: nil, sort: nil, widget: nil, dashboard: nil))
        try assertShape(sent(), method: "POST", path: "/task-list/create", body: #"{"name":"Compra"}"#)

        _ = try await repo.update(UpdateTaskListRequest(id: 2, name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: true))
        try assertShape(sent(), method: "PATCH", path: "/task-list/update",
                        body: ##"{"color":"#6923E2","dashboard":true,"id":2,"name":"Compra","sort":"custom","widget":true}"##)

        try await repo.delete(id: 2)
        try assertShape(sent(), method: "DELETE", path: "/task-list/delete", body: #"{"id":2}"#)

        _ = try await repo.users(taskListId: 2)
        try assertShape(sent(), method: "GET", path: "/task-list/user", query: [("task_list_id", "2")], body: nil)

        _ = try await repo.invite(taskListId: 2, email: "invitado@homita.example")
        try assertShape(sent(), method: "POST", path: "/task-list/user",
                        body: #"{"email":"invitado@homita.example","task_list_id":2}"#)

        try await repo.removeUser(taskListId: 2, userId: 9)
        try assertShape(sent(), method: "DELETE", path: "/task-list/user",
                        body: #"{"task_list_id":2,"user_id":9}"#)
    }

    func testTaskListUsersDecodeTluIdMembers() async throws {
        setUpStub()
        let repo = TaskListRepository(client: makeTestClient())

        // Regresión R1-01: `GET task-list/user` responde miembros con `tlu_id` (no `[]`).
        let members = try await repo.users(taskListId: 2)
        try assertShape(sent(), method: "GET", path: "/task-list/user", query: [("task_list_id", "2")], body: nil)
        XCTAssertEqual(members.map(\.id), [10, 11])
        XCTAssertEqual(members.map(\.role), ["owner", "viewer"])
    }

    func testTaskShapes() async throws {
        setUpStub()
        let client = makeTestClient()
        let repo = TaskRepository(client: client)

        _ = try await repo.index()
        try assertShape(sent(), method: "GET", path: "/task", body: nil)

        // `task_list_id` por query, nunca body (desviación 9).
        _ = try await repo.index(taskListId: 2)
        try assertShape(sent(), method: "GET", path: "/task", query: [("task_list_id", "2")], body: nil)

        _ = try await repo.detail(id: 7)
        try assertShape(sent(), method: "GET", path: "/task/detail", query: [("id", "7")], body: nil)

        _ = try await repo.create(CreateTaskRequest(task_list_id: 2, title: "Leche"))
        try assertShape(sent(), method: "POST", path: "/task/create",
                        body: #"{"task_list_id":2,"title":"Leche"}"#)

        _ = try await repo.update(UpdateTaskRequest(id: 7, title: "Leche entera"))
        try assertShape(sent(), method: "PATCH", path: "/task/update",
                        body: #"{"id":7,"title":"Leche entera"}"#)

        _ = try await repo.complete(CompleteTaskRequest(id: 7, completed: true))
        try assertShape(sent(), method: "PATCH", path: "/task/complete",
                        body: #"{"completed":true,"id":7}"#)

        _ = try await repo.order(OrderTaskRequest(id: 7, position: 0))
        try assertShape(sent(), method: "PATCH", path: "/task/order",
                        body: #"{"id":7,"position":0}"#)

        try await repo.delete(id: 7)
        try assertShape(sent(), method: "DELETE", path: "/task/delete", body: #"{"id":7}"#)
    }

    // MARK: - Personas

    func testPersonShapes() async throws {
        setUpStub()
        let client = makeTestClient()
        let repo = PersonRepository(client: client)

        _ = try await repo.index()
        try assertShape(sent(), method: "GET", path: "/person", body: nil)

        _ = try await repo.create(CreatePersonRequest(name: "Ana", color: "#FF0000"))
        try assertShape(sent(), method: "POST", path: "/person/create",
                        body: ##"{"color":"#FF0000","name":"Ana"}"##)

        _ = try await repo.update(UpdatePersonRequest(id: 1, name: "Ana", color: "#FF0000"))
        try assertShape(sent(), method: "PATCH", path: "/person/update",
                        body: ##"{"color":"#FF0000","id":1,"name":"Ana"}"##)

        try await repo.delete(id: 1)
        try assertShape(sent(), method: "DELETE", path: "/person/delete", body: #"{"id":1}"#)
    }
}
