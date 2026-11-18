import Foundation

// DTOs de escritura del contrato PHP. Claves snake_case literales (sin key strategies); los
// opcionales ausentes se omiten del JSON (igual que Gson en Android). En GET nunca van body:
// los filtros se mandan como query (desviación 9: el runtime de Edge descarta body en GET).

// MARK: - Usuario

public struct AuthRequest: Encodable, Equatable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct RegisterRequest: Encodable, Equatable {
    public let name: String
    public let email: String
    public let password: String
    /// Código de invitación (0023). Nil → registro con creación; se omite del JSON.
    public let invitationCode: String?

    public init(name: String, email: String, password: String, invitationCode: String? = nil) {
        self.name = name
        self.email = email
        self.password = password
        self.invitationCode = invitationCode
    }

    enum CodingKeys: String, CodingKey {
        case name, email, password
        case invitationCode = "invitation_code"
    }
}

public struct UpdateProfileRequest: Encodable, Equatable {
    public let name: String
    public let email: String
    public let password: String?

    public init(name: String, email: String, password: String?) {
        self.name = name
        self.email = email
        self.password = password
    }
}

// MARK: - Calendarios

public struct CreateCalendarRequest: Encodable, Equatable {
    public let name: String
    public let color: String
    public let widget: Bool
    public let dashboard: Bool

    public init(name: String, color: String, widget: Bool, dashboard: Bool) {
        self.name = name
        self.color = color
        self.widget = widget
        self.dashboard = dashboard
    }
}

public struct UpdateCalendarRequest: Encodable, Equatable {
    public let id: Int
    public let name: String
    public let color: String
    public let widget: Bool
    public let dashboard: Bool

    public init(id: Int, name: String, color: String, widget: Bool, dashboard: Bool) {
        self.id = id
        self.name = name
        self.color = color
        self.widget = widget
        self.dashboard = dashboard
    }
}

public struct DeleteRequest: Encodable, Equatable {
    public let id: Int

    public init(id: Int) {
        self.id = id
    }
}

public struct CreateCalendarUserRequest: Encodable, Equatable {
    public let calendar_id: Int
    public let email: String

    public init(calendar_id: Int, email: String) {
        self.calendar_id = calendar_id
        self.email = email
    }
}

public struct DeleteCalendarUserRequest: Encodable, Equatable {
    public let calendar_id: Int
    public let user_id: Int

    public init(calendar_id: Int, user_id: Int) {
        self.calendar_id = calendar_id
        self.user_id = user_id
    }
}

/// `PATCH calendar/user` body `{calendar_id,user_id,can_edit}` (0029): permiso de un miembro.
public struct UpdateCalendarUserAccessRequest: Encodable, Equatable {
    public let calendar_id: Int
    public let user_id: Int
    public let can_edit: Bool

    public init(calendar_id: Int, user_id: Int, can_edit: Bool) {
        self.calendar_id = calendar_id
        self.user_id = user_id
        self.can_edit = can_edit
    }
}

// MARK: - Eventos

/// v1 sin "modo IA": `POST event/create` exige `title` + `date_at` (la Edge devuelve 400 si solo
/// llega `text`). `alarm` = null|0|10|20|30|40|60 minutos.
public struct CreateEventRequest: Encodable, Equatable {
    public let calendar_id: Int
    public let title: String
    public let date_at: String
    public let alarm: Int?
    public let person_ids: [Int]

    public init(calendar_id: Int, title: String, date_at: String, alarm: Int?, person_ids: [Int]) {
        self.calendar_id = calendar_id
        self.title = title
        self.date_at = date_at
        self.alarm = alarm
        self.person_ids = person_ids
    }
}

public struct UpdateEventRequest: Encodable, Equatable {
    public let id: Int
    public let title: String
    public let date_at: String
    public let alarm: Int?
    public let person_ids: [Int]

    public init(id: Int, title: String, date_at: String, alarm: Int?, person_ids: [Int]) {
        self.id = id
        self.title = title
        self.date_at = date_at
        self.alarm = alarm
        self.person_ids = person_ids
    }
}

public struct SetEventAlarmRequest: Encodable, Equatable {
    public let event_id: Int
    public let alarm: Int?

    public init(event_id: Int, alarm: Int?) {
        self.event_id = event_id
        self.alarm = alarm
    }
}

// MARK: - Rutinas

public struct CreateRoutineRequest: Encodable, Equatable {
    public let calendar_id: Int
    public let title: String
    public let frequency: String
    public let interval: Int
    public let days: [Int]
    public let time: String
    public let start_date: String
    public let end_date: String?
    public let active: Bool
    public let alarm: Int?
    public let person_ids: [Int]

    public init(
        calendar_id: Int, title: String, frequency: String, interval: Int, days: [Int], time: String,
        start_date: String, end_date: String?, active: Bool, alarm: Int?, person_ids: [Int]
    ) {
        self.calendar_id = calendar_id
        self.title = title
        self.frequency = frequency
        self.interval = interval
        self.days = days
        self.time = time
        self.start_date = start_date
        self.end_date = end_date
        self.active = active
        self.alarm = alarm
        self.person_ids = person_ids
    }
}

/// `PATCH routine/update` no lleva `alarm`: el aviso se cambia aparte con `PATCH routine/alarm`
/// (misma semántica que Android).
public struct UpdateRoutineRequest: Encodable, Equatable {
    public let id: Int
    public let title: String
    public let frequency: String
    public let interval: Int
    public let days: [Int]
    public let time: String
    public let start_date: String
    public let end_date: String?
    public let active: Bool
    public let person_ids: [Int]

    public init(
        id: Int, title: String, frequency: String, interval: Int, days: [Int], time: String,
        start_date: String, end_date: String?, active: Bool, person_ids: [Int]
    ) {
        self.id = id
        self.title = title
        self.frequency = frequency
        self.interval = interval
        self.days = days
        self.time = time
        self.start_date = start_date
        self.end_date = end_date
        self.active = active
        self.person_ids = person_ids
    }
}

public struct SetRoutineAlarmRequest: Encodable, Equatable {
    public let id: Int
    public let alarm: Int?

    public init(id: Int, alarm: Int?) {
        self.id = id
        self.alarm = alarm
    }
}

// MARK: - Personas

public struct CreatePersonRequest: Encodable, Equatable {
    public let name: String
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct UpdatePersonRequest: Encodable, Equatable {
    public let id: Int
    public let name: String
    public let color: String

    public init(id: Int, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

// MARK: - Listas de tareas

public struct CreateTaskListRequest: Encodable, Equatable {
    public let name: String
    public let color: String?
    public let sort: String?
    public let widget: Bool?
    public let dashboard: Bool?

    public init(name: String, color: String?, sort: String?, widget: Bool?, dashboard: Bool?) {
        self.name = name
        self.color = color
        self.sort = sort
        self.widget = widget
        self.dashboard = dashboard
    }
}

public struct UpdateTaskListRequest: Encodable, Equatable {
    public let id: Int
    public let name: String
    public let color: String
    public let sort: String
    public let widget: Bool?
    public let dashboard: Bool?

    public init(id: Int, name: String, color: String, sort: String, widget: Bool?, dashboard: Bool?) {
        self.id = id
        self.name = name
        self.color = color
        self.sort = sort
        self.widget = widget
        self.dashboard = dashboard
    }
}

public struct CreateTaskListUserRequest: Encodable, Equatable {
    public let task_list_id: Int
    public let email: String

    public init(task_list_id: Int, email: String) {
        self.task_list_id = task_list_id
        self.email = email
    }
}

public struct DeleteTaskListUserRequest: Encodable, Equatable {
    public let task_list_id: Int
    public let user_id: Int

    public init(task_list_id: Int, user_id: Int) {
        self.task_list_id = task_list_id
        self.user_id = user_id
    }
}

/// `PATCH task-list/user` body `{task_list_id,user_id,can_edit}` (0029): permiso de un miembro.
public struct UpdateTaskListUserAccessRequest: Encodable, Equatable {
    public let task_list_id: Int
    public let user_id: Int
    public let can_edit: Bool

    public init(task_list_id: Int, user_id: Int, can_edit: Bool) {
        self.task_list_id = task_list_id
        self.user_id = user_id
        self.can_edit = can_edit
    }
}

// MARK: - Tareas

public struct CreateTaskRequest: Encodable, Equatable {
    public let task_list_id: Int
    public let title: String
    /// Personas asignadas (0025). nil = no enviar; [] = ninguna.
    public let person_ids: [Int]?

    public init(task_list_id: Int, title: String, person_ids: [Int]? = nil) {
        self.task_list_id = task_list_id
        self.title = title
        self.person_ids = person_ids
    }
}

public struct UpdateTaskRequest: Encodable, Equatable {
    public let id: Int
    public let title: String
    /// Personas asignadas (0025). nil = no tocar las actuales; [] = quitar todas.
    public let person_ids: [Int]?

    public init(id: Int, title: String, person_ids: [Int]? = nil) {
        self.id = id
        self.title = title
        self.person_ids = person_ids
    }
}

public struct CompleteTaskRequest: Encodable, Equatable {
    public let id: Int
    public let completed: Bool

    public init(id: Int, completed: Bool) {
        self.id = id
        self.completed = completed
    }
}

public struct OrderTaskRequest: Encodable, Equatable {
    public let id: Int
    public let position: Int

    public init(id: Int, position: Int) {
        self.id = id
        self.position = position
    }
}
