import Foundation

/// Filtros de lectura: SIEMPRE como query (GET sin body). `start_date`/`end_date` = epoch de 10
/// dígitos (hora local como epoch, ver `LocalClock`); `timezone` = identificador IANA.
public struct EventFilters: Equatable, Sendable {
    public var calendarId: Int?
    public var search: String?
    public var startDate: String?
    public var endDate: String?
    public var limit: Int?
    public var offset: Int?
    public var orderMode: String?
    public var routine: Bool?
    public var widget: Bool?
    public var dashboard: Bool?
    public var timezone: String?

    public init(
        calendarId: Int? = nil, search: String? = nil, startDate: String? = nil, endDate: String? = nil,
        limit: Int? = nil, offset: Int? = nil, orderMode: String? = nil, routine: Bool? = nil,
        widget: Bool? = nil, dashboard: Bool? = nil, timezone: String? = nil
    ) {
        self.calendarId = calendarId
        self.search = search
        self.startDate = startDate
        self.endDate = endDate
        self.limit = limit
        self.offset = offset
        self.orderMode = orderMode
        self.routine = routine
        self.widget = widget
        self.dashboard = dashboard
        self.timezone = timezone
    }

    var queryItems: [URLQueryItem] {
        query([
            ("calendar_id", calendarId.map(String.init)),
            ("search", search),
            ("start_date", startDate),
            ("end_date", endDate),
            ("limit", limit.map(String.init)),
            ("offset", offset.map(String.init)),
            ("order_mode", orderMode),
            ("routine", routine.map { $0 ? "true" : "false" }),
            ("widget", widget.map { $0 ? "true" : "false" }),
            ("dashboard", dashboard.map { $0 ? "true" : "false" }),
            ("timezone", timezone)
        ])
    }
}

/// Pares nombre/valor a `URLQueryItem`, omitiendo los ausentes.
func query(_ pairs: [(String, String?)]) -> [URLQueryItem] {
    pairs.compactMap { name, value in
        value.map { URLQueryItem(name: name, value: $0) }
    }
}
