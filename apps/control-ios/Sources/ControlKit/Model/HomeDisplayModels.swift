import Foundation

/// Horario de la pantalla (minutos desde medianoche), con los mismos nombres que la app del marco.
public struct DisplaySchedule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var weekdayOn: Int
    public var weekdayOff: Int
    public var weekendOn: Int
    public var weekendOff: Int
    public var screenOff: Bool

    public init(enabled: Bool, weekdayOn: Int, weekdayOff: Int, weekendOn: Int, weekendOff: Int, screenOff: Bool) {
        self.enabled = enabled
        self.weekdayOn = weekdayOn
        self.weekdayOff = weekdayOff
        self.weekendOn = weekendOn
        self.weekendOff = weekendOff
        self.screenOff = screenOff
    }

    /// Valores por defecto del marco (07:00–23:00 entre semana; 08:30–23:30 en fin de semana).
    public static let standard = DisplaySchedule(enabled: false, weekdayOn: 420, weekdayOff: 1380, weekendOn: 510, weekendOff: 1410, screenOff: false)
}

/// Ubicación del tiempo de la pantalla (la del hogar por defecto).
public struct DisplayLocation: Codable, Equatable, Sendable {
    public let name: String
    public let detail: String
    public let latitude: Double
    public let longitude: Double
}

/// Ajustes de la pantalla. El servidor guarda el objeto entero: al editar hay que devolver también lo que no se toca
/// (la ubicación). Brillo nil = automático.
public struct DisplaySettings: Codable, Equatable, Sendable {
    public var brightness: Double?
    public var schedule: DisplaySchedule?
    public var location: DisplayLocation?

    public init(brightness: Double?, schedule: DisplaySchedule?, location: DisplayLocation?) {
        self.brightness = brightness
        self.schedule = schedule
        self.location = location
    }
}

/// Una pantalla del hogar (`GET home/display`).
public struct HomeDisplay: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let settings: DisplaySettings
    public let lastSeenAt: String?
    public let calendarIds: [Int]
    public let taskListIds: [Int]
    /// Canal de actualización (`estable` | `pruebas`); nil si el servidor es anterior a 0053.
    public let updateChannel: String?
    /// Versión que la pantalla tiene instalada (informe de la app, 0051/0053).
    public let appVersionCode: Int?
    public let appVersionName: String?
    /// Último resultado de la comprobación/instalación que reportó la pantalla (p. ej. «instalada 4»).
    public let lastUpdateResult: String?

    public init(id: Int, name: String, settings: DisplaySettings, lastSeenAt: String?, calendarIds: [Int], taskListIds: [Int],
                updateChannel: String? = nil, appVersionCode: Int? = nil, appVersionName: String? = nil, lastUpdateResult: String? = nil) {
        self.id = id
        self.name = name
        self.settings = settings
        self.lastSeenAt = lastSeenAt
        self.calendarIds = calendarIds
        self.taskListIds = taskListIds
        self.updateChannel = updateChannel
        self.appVersionCode = appVersionCode
        self.appVersionName = appVersionName
        self.lastUpdateResult = lastUpdateResult
    }

    enum CodingKeys: String, CodingKey {
        case id, name, settings
        case lastSeenAt = "last_seen_at"
        case calendarIds = "calendar_ids"
        case taskListIds = "task_list_ids"
        case updateChannel = "update_channel"
        case appVersionCode = "app_version_code"
        case appVersionName = "app_version_name"
        case lastUpdateResult = "last_update_result"
    }
}

/// Resultado de confirmar una vinculación (`POST home/display/link-confirm`, 201).
public struct DisplayLinked: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let homeId: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case homeId = "home_id"
    }
}

/// Body de `POST home/display/link-confirm`: el código de 6 dígitos que muestra la pantalla.
public struct LinkDisplayBody: Encodable, Equatable, Sendable {
    public let code: String
    public let name: String
}

/// Body de `PATCH home/display/update`. Lo que no se envía no cambia (nil se omite).
public struct UpdateDisplayBody: Encodable, Equatable, Sendable {
    public let id: Int
    public let name: String?
    public let settings: DisplaySettings?
    public let calendarIds: [Int]?
    public let taskListIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, name, settings
        case calendarIds = "calendar_ids"
        case taskListIds = "task_list_ids"
    }
}

/// Body de `POST home/display/revoke`.
public struct RevokeDisplayBody: Encodable, Equatable, Sendable {
    public let id: Int
}
