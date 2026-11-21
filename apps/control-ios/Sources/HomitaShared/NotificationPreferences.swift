import Foundation

/// Preferencias de «Ajustes › Notificaciones». Se guardan en el App Group para que los widgets
/// sepan si están desactivados. Todo se puede apagar desde Ajustes.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    /// Avisos de eventos (según la alarma de cada evento).
    public var eventReminders: Bool
    /// Avisos de rutinas (según la alarma de cada rutina).
    public var routineReminders: Bool
    /// Resumen diario de tareas pendientes.
    public var taskDigest: Bool
    public var taskDigestHour: Int
    public var taskDigestMinute: Int
    /// Resumen diario de lo asignado a mí (tareas pendientes y eventos de hoy). Desactivado por defecto.
    public var dailySummary: Bool
    public var dailySummaryHour: Int
    public var dailySummaryMinute: Int
    /// Datos de los widgets (Rutinas de hoy y Accesos rápidos).
    public var widgets: Bool
    /// Rutinas en la pantalla de bloqueo (Live Activity).
    public var routineLiveActivity: Bool

    public init(
        eventReminders: Bool = true,
        routineReminders: Bool = true,
        taskDigest: Bool = false,
        taskDigestHour: Int = 9,
        taskDigestMinute: Int = 0,
        dailySummary: Bool = false,
        dailySummaryHour: Int = 8,
        dailySummaryMinute: Int = 0,
        widgets: Bool = true,
        routineLiveActivity: Bool = true
    ) {
        self.eventReminders = eventReminders
        self.routineReminders = routineReminders
        self.taskDigest = taskDigest
        self.taskDigestHour = min(max(taskDigestHour, 0), 23)
        self.taskDigestMinute = min(max(taskDigestMinute, 0), 59)
        self.dailySummary = dailySummary
        self.dailySummaryHour = min(max(dailySummaryHour, 0), 23)
        self.dailySummaryMinute = min(max(dailySummaryMinute, 0), 59)
        self.widgets = widgets
        self.routineLiveActivity = routineLiveActivity
    }

    /// Decodificación tolerante: un JSON guardado sin los campos nuevos conserva lo existente y usa los valores de fábrica.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            eventReminders: try c.decodeIfPresent(Bool.self, forKey: .eventReminders) ?? true,
            routineReminders: try c.decodeIfPresent(Bool.self, forKey: .routineReminders) ?? true,
            taskDigest: try c.decodeIfPresent(Bool.self, forKey: .taskDigest) ?? false,
            taskDigestHour: try c.decodeIfPresent(Int.self, forKey: .taskDigestHour) ?? 9,
            taskDigestMinute: try c.decodeIfPresent(Int.self, forKey: .taskDigestMinute) ?? 0,
            dailySummary: try c.decodeIfPresent(Bool.self, forKey: .dailySummary) ?? false,
            dailySummaryHour: try c.decodeIfPresent(Int.self, forKey: .dailySummaryHour) ?? 8,
            dailySummaryMinute: try c.decodeIfPresent(Int.self, forKey: .dailySummaryMinute) ?? 0,
            widgets: try c.decodeIfPresent(Bool.self, forKey: .widgets) ?? true,
            routineLiveActivity: try c.decodeIfPresent(Bool.self, forKey: .routineLiveActivity) ?? true
        )
    }

    /// ¿Hay algún aviso local activo? (decide si hace falta pedir permiso al sistema).
    public var anyReminder: Bool { eventReminders || routineReminders || taskDigest || dailySummary }

    /// Hora del resumen como `HH:mm`.
    public var taskDigestTimeText: String {
        String(format: "%02d:%02d", taskDigestHour, taskDigestMinute)
    }

    /// Hora del resumen diario como `HH:mm`.
    public var dailySummaryTimeText: String {
        String(format: "%02d:%02d", dailySummaryHour, dailySummaryMinute)
    }
}

/// Lectura y escritura de las preferencias. Por defecto usa los `UserDefaults` del App Group.
public struct NotificationPreferencesStore {
    public static let key = "notification_preferences_v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = HomitaShared.defaults) {
        self.defaults = defaults
    }

    /// Preferencias guardadas; las de fábrica si no hay nada o no se pueden leer.
    public func load() -> NotificationPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
            return NotificationPreferences()
        }
        return value
    }

    public func save(_ preferences: NotificationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
