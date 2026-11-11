import Foundation

// Modelos Codable que replican los shapes PHP del contrato (`supabase/migrations/0005_read_rpcs.sql`
// y `supabase/functions/api/usecases/*.ts`).
// Los nombres de propiedad van en snake_case a la imagen de `apps/control/.../Models.kt`: son el
// contrato literal (sin CodingKeys ni key strategies, cero riesgo de traducción). Los campos con
// formas tolerantes llegan como `FlexBool?`/`FlexInt?` (0/1 o bool JSON; legacy null).

// MARK: - Config y usuario

/// `GET config` → `{allow_registration: bool}`.
public struct ConfigResponse: Codable, Equatable {
    public let allow_registration: FlexBool?

    public var allowRegistration: Bool { allow_registration?.value ?? false }
}

/// `POST user/auth` y `POST user/create` → `{id,name,email,token,…}`; la Edge añade
/// `refresh_token` en `user/auth` (desviación 5; `user/create` no lo trae).
public struct UserResponse: Codable, Equatable {
    public let id: Int
    public let name: String
    public let email: String
    public let token: String?
    public let refresh_token: String?
    public let created_at: String?
    public let updated_at: String?
}

// MARK: - Calendarios

/// `GET calendar` → `{id,name,color,token,created_at,updated_at,widget,dashboard,upcoming_event_count}`;
/// `GET calendar/detail` llega sin widget/dashboard/count (se tolera).
public struct CalendarEntry: Codable, Equatable {
    public let id: Int
    public let name: String
    public let color: String
    public let token: String?
    public let created_at: String?
    public let updated_at: String?
    public let widget: FlexBool?
    public let dashboard: FlexBool?
    public let upcoming_event_count: FlexInt?

    public var showsInWidget: Bool { widget?.value ?? true }
    public var showsInDashboard: Bool { dashboard?.value ?? true }
    public var upcomingEventCount: Int { upcoming_event_count?.value ?? 0 }
}

/// `GET calendar/user` → `[{cu_id,user_id,name,email,role}]`; `GET task-list/user` usa
/// `tlu_id` como clave de la fila de membresía (0005_read_rpcs.sql `get_task_list_users`).
/// Se aceptan ambas claves (opcionales): `id` prefiere `cu_id`, luego `tlu_id`.
public struct MemberEntry: Codable, Equatable {
    public let cu_id: Int?
    public let tlu_id: Int?
    public let user_id: Int
    public let name: String
    public let email: String
    public let role: String

    /// Id estable de la fila de membresía para `ForEach` (una sola keypath).
    public var id: Int { cu_id ?? tlu_id ?? user_id }

    /// `role == "owner"` en el payload de miembros (matriz owner/viewer del contrato).
    public var isOwner: Bool { role == "owner" }
}

// MARK: - Personas

/// `GET person` → `{id,user_id,name,color,created_at,updated_at,editable}`; dentro de eventos y
/// rutinas solo llega `{id,user_id,name,color}` (se tolera).
public struct PersonEntry: Codable, Equatable, Identifiable {
    public let id: Int
    public let user_id: Int
    public let name: String
    public let color: String
    public let created_at: String?
    public let updated_at: String?
    public let editable: FlexBool?

    public var isEditable: Bool { editable?.value ?? false }
}

// MARK: - Eventos

/// `GET event` → con `calendar_color`/`calendar_name`; `GET event/detail` sin ellos (se tolera).
/// `alarm` = minutos antes | 0 | null (sin aviso). `persons` = personas asignadas.
public struct EventEntry: Codable, Equatable, Identifiable {
    public let id: Int
    public let calendar_id: Int
    public let title: String
    public let date_at: String
    public let created_at: String?
    public let updated_at: String?
    public let routine_id: Int?
    public let routine_date: String?
    public let calendar_color: String?
    public let calendar_name: String?
    public let alarm: Int?
    public let persons: [PersonEntry]?
}

// MARK: - Rutinas

/// `GET routine` → `{id,calendar_id,title,days,time,start_date,end_date,active,available_from,
/// frequency,interval,calendar_name,calendar_color,alarm,persons}`. `frequency`/`interval` son
/// null en backends antiguos (se tolera). `days` = días ISO 1-7 (solo frecuencia semanal).
public struct RoutineEntry: Codable, Equatable, Identifiable {
    public let id: Int
    public let calendar_id: Int
    public let title: String
    public let days: [Int]?
    public let time: String
    public let start_date: String
    public let end_date: String?
    public let active: FlexBool?
    public let available_from: String?
    public let frequency: String?
    public let interval: FlexInt?
    public let created_at: String?
    public let updated_at: String?
    public let calendar_name: String?
    public let calendar_color: String?
    public let alarm: Int?
    public let persons: [PersonEntry]?

    public var isActive: Bool { active?.value ?? true }
    public var weekdays: [Int] { days ?? [] }
    public var intervalValue: Int { interval?.value ?? 1 }
}

// MARK: - Listas de tareas y tareas

/// `GET task-list` → con widget/dashboard/pending_task_count; `GET task-list/detail` sin ellos.
public struct TaskListEntry: Codable, Equatable {
    public let id: Int
    public let name: String
    public let color: String
    public let token: String?
    public let sort: String
    public let created_at: String?
    public let updated_at: String?
    public let widget: FlexBool?
    public let dashboard: FlexBool?
    public let pending_task_count: FlexInt?

    public var showsInWidget: Bool { widget?.value ?? true }
    public var showsInDashboard: Bool { dashboard?.value ?? true }
    public var pendingTaskCount: Int { pending_task_count?.value ?? 0 }
}

/// `GET task` → `{id,task_list_id,title,completed_at,created_at,updated_at,order,
/// task_list_color,task_list_name}`. `completed_at` null = pendiente.
public struct TaskEntry: Codable, Equatable, Identifiable {
    public let id: Int
    public let task_list_id: Int
    public let title: String
    public let completed_at: String?
    public let created_at: String?
    public let updated_at: String?
    public let order: FlexInt?
    public let task_list_color: String?
    public let task_list_name: String?
    /// Personas asignadas (`GET task`, migración 0024). Ausente en respuestas antiguas → nil.
    public let persons: [PersonEntry]?

    public var isCompleted: Bool { completed_at != nil }
    public var orderValue: Int { order?.value ?? 0 }
}

// MARK: - Respuestas de escritura

/// `{"success":true}` (deletes) y `{"status":"ok"}` (retirada de miembro): mismo shape tolerante.
public struct OkResponse: Codable, Equatable {
    public let success: FlexBool?
    public let status: String?
}
