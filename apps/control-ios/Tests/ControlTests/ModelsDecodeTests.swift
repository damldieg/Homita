import XCTest
@testable import ControlKit

/// Decodificación de los modelos con fixtures JSON en los shapes del contrato
/// (`supabase/migrations/0005_read_rpcs.sql`; sin datos personales: demo).
final class ModelsDecodeTests: XCTestCase {
    func testConfigResponse() throws {
        XCTAssertFalse(try decodeFixture(ConfigResponse.self, #"{"allow_registration":false}"#).allowRegistration)
        XCTAssertTrue(try decodeFixture(ConfigResponse.self, #"{"allow_registration":true}"#).allowRegistration)
        // Backends sin la clave: por defecto no se ofrece registro.
        XCTAssertFalse(try decodeFixture(ConfigResponse.self, "{}").allowRegistration)
    }

    func testUserResponseWithRefreshToken() throws {
        let user = try decodeFixture(UserResponse.self, """
        {"id":1,"name":"Demo","email":"demo@homita.example","token":"jwt-access",
         "refresh_token":"rt-1","created_at":"2026-11-08 09:30:00","updated_at":"2026-11-08 09:30:00"}
        """)
        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.token, "jwt-access")
        XCTAssertEqual(user.refresh_token, "rt-1")
    }

    func testCalendarEntryWithFlags() throws {
        let calendar = try decodeFixture(CalendarEntry.self, """
        {"id":3,"name":"Familia","color":"#6923E2","token":"t","created_at":"2026-11-08 09:30:00",
         "updated_at":"2026-11-08 09:30:00","widget":0,"dashboard":1,"upcoming_event_count":3}
        """)
        XCTAssertFalse(calendar.showsInWidget)
        XCTAssertTrue(calendar.showsInDashboard)
        XCTAssertEqual(calendar.upcomingEventCount, 3)
    }

    func testCalendarDetailToleratesMissingFields() throws {
        let calendar = try decodeFixture(CalendarEntry.self, ##"{"id":3,"name":"Familia","color":"#6923E2"}"##)
        XCTAssertTrue(calendar.showsInWidget)
        XCTAssertEqual(calendar.upcomingEventCount, 0)
    }

    func testMemberEntry() throws {
        let member = try decodeFixture(MemberEntry.self, #"{"cu_id":10,"user_id":2,"name":"Demo","email":"demo@homita.example","role":"owner"}"#)
        XCTAssertEqual(member.role, "owner")
        XCTAssertEqual(member.user_id, 2)
        XCTAssertEqual(member.id, 10)
    }

    func testMemberEntryTluIdPayload() throws {
        // Regresión R1-01: `GET task-list/user` manda `tlu_id`, no `cu_id` (0005_read_rpcs.sql).
        let member = try decodeFixture(MemberEntry.self, #"{"tlu_id":11,"user_id":2,"name":"Demo","email":"demo@homita.example","role":"viewer"}"#)
        XCTAssertEqual(member.id, 11)
        XCTAssertNil(member.cu_id)
        // Si llegan ambas claves se prefiere `cu_id`.
        let both = try decodeFixture(MemberEntry.self, #"{"cu_id":10,"tlu_id":11,"user_id":2,"name":"Demo","email":"demo@homita.example","role":"owner"}"#)
        XCTAssertEqual(both.id, 10)
    }

    func testPersonEntryEditableBool() throws {
        let editable = try decodeFixture(PersonEntry.self, ##"{"id":1,"user_id":1,"name":"Ana","color":"#FF0000","editable":true}"##)
        XCTAssertTrue(editable.isEditable)
        let shared = try decodeFixture(PersonEntry.self, ##"{"id":2,"user_id":9,"name":"Bea","color":"#00FF00","editable":false}"##)
        XCTAssertFalse(shared.isEditable)
    }

    func testEventEntryWithPersonsAndAlarm() throws {
        let event = try decodeFixture(EventEntry.self, """
        {"id":5,"calendar_id":3,"title":"Reunión","date_at":"2026-11-08 09:30:00",
         "created_at":"2026-11-08 09:00:00","updated_at":"2026-11-08 09:00:00",
         "routine_id":null,"routine_date":null,"calendar_color":"#6923E2","calendar_name":"Familia",
         "alarm":10,"persons":[{"id":1,"user_id":1,"name":"Ana","color":"#FF0000"}]}
        """)
        XCTAssertEqual(event.alarm, 10)
        XCTAssertNil(event.routine_id)
        XCTAssertEqual(event.persons?.count, 1)
        XCTAssertNotNil(PHPDateTime.parse(event.date_at))
    }

    func testEventDetailMinimal() throws {
        let event = try decodeFixture(EventEntry.self, #"{"id":5,"calendar_id":3,"title":"E","date_at":"2026-11-08 09:30:00","alarm":null}"#)
        XCTAssertNil(event.alarm)
    }

    func testRoutineEntryTolerantTypes() throws {
        let routine = try decodeFixture(RoutineEntry.self, """
        {"id":4,"calendar_id":3,"title":"Rutina","days":[1,5],"time":"09:00","start_date":"2026-11-02",
         "end_date":null,"active":1,"available_from":"2026-11-02 00:00:00","frequency":"weekly",
         "interval":"2","created_at":"2026-11-02 00:00:00","updated_at":"2026-11-02 00:00:00",
         "calendar_name":"Familia","calendar_color":"#6923E2","alarm":null,
         "persons":[{"id":1,"user_id":1,"name":"Ana","color":"#FF0000"}]}
        """)
        XCTAssertTrue(routine.isActive)
        XCTAssertEqual(routine.weekdays, [1, 5])
        XCTAssertEqual(routine.intervalValue, 2) // "2" string tolerado (FlexInt)
        XCTAssertEqual(routine.frequency, "weekly")
    }

    func testTaskListEntryFlags() throws {
        let list = try decodeFixture(TaskListEntry.self, """
        {"id":2,"name":"Compra","color":"#6923E2","token":"t","sort":"custom",
         "created_at":"2026-11-08 09:30:00","updated_at":"2026-11-08 09:30:00",
         "widget":0,"dashboard":1,"pending_task_count":4}
        """)
        XCTAssertFalse(list.showsInWidget)
        XCTAssertEqual(list.pendingTaskCount, 4)
        XCTAssertEqual(list.sort, "custom")
    }

    func testTaskEntryCompletedStates() throws {
        let pending = try decodeFixture(TaskEntry.self, #"{"id":7,"task_list_id":2,"title":"Leche","completed_at":null,"order":1}"#)
        XCTAssertFalse(pending.isCompleted)
        XCTAssertEqual(pending.orderValue, 1)
        let done = try decodeFixture(TaskEntry.self, #"{"id":8,"task_list_id":2,"title":"Pan","completed_at":"2026-11-08 09:30:00","order":"2"}"#)
        XCTAssertTrue(done.isCompleted)
        XCTAssertEqual(done.orderValue, 2) // "2" string tolerado (FlexInt)
    }

    func testOkResponseShapes() throws {
        XCTAssertTrue(try decodeFixture(OkResponse.self, #"{"success":true}"#).success?.value == true)
        XCTAssertEqual(try decodeFixture(OkResponse.self, #"{"status":"ok"}"#).status, "ok")
    }
}
