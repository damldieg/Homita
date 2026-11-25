import Foundation

/// Fase de una rutina de hoy según su hora de inicio (misma regla que `RoutineStatus` en la app).
public enum SnapshotRoutinePhase: String, Codable, Equatable, Sendable {
    /// Ya pasó la ventana de una hora.
    case done
    /// Dentro de la hora desde el inicio.
    case now
    /// Empieza en menos de una hora.
    case soon
    /// Más tarde.
    case later
    /// Sin hora fija.
    case anytime
}

/// Foto del día que la app deja para los widgets y la Live Activity (JSON en el App Group).
/// No lleva secretos: solo títulos, horas y colores.
public struct HomitaSnapshot: Codable, Equatable, Sendable {
    public struct Routine: Codable, Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let colorHex: String
        /// Inicio de hoy; `nil` = sin hora fija.
        public let start: Date?
        public let persons: [String]
        /// La persona vinculada a la cuenta de este iPhone está asignada a la rutina.
        public let assignedToMe: Bool

        public init(
            id: Int, title: String, colorHex: String, start: Date?, persons: [String] = [], assignedToMe: Bool = false
        ) {
            self.id = id
            self.title = title
            self.colorHex = colorHex
            self.start = start
            self.persons = persons
            self.assignedToMe = assignedToMe
        }

        // `assignedToMe` es posterior a la primera versión del fichero: un snapshot viejo se sigue leyendo.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            colorHex = try container.decode(String.self, forKey: .colorHex)
            start = try container.decodeIfPresent(Date.self, forKey: .start)
            persons = try container.decodeIfPresent([String].self, forKey: .persons) ?? []
            assignedToMe = try container.decodeIfPresent(Bool.self, forKey: .assignedToMe) ?? false
        }

        /// Fin de la ventana «en curso».
        public var end: Date? { start?.addingTimeInterval(HomitaShared.routineWindow) }

        public func phase(at now: Date) -> SnapshotRoutinePhase {
            guard let start else { return .anytime }
            if now > start.addingTimeInterval(HomitaShared.routineWindow) { return .done }
            if now >= start { return .now }
            if start.timeIntervalSince(now) <= HomitaShared.routineSoonWindow { return .soon }
            return .later
        }
    }

    public struct Event: Codable, Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let colorHex: String
        public let start: Date

        public init(id: Int, title: String, colorHex: String, start: Date) {
            self.id = id
            self.title = title
            self.colorHex = colorHex
            self.start = start
        }
    }

    public struct TaskItem: Codable, Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let listName: String
        public let colorHex: String

        public init(id: Int, title: String, listName: String, colorHex: String) {
            self.id = id
            self.title = title
            self.listName = listName
            self.colorHex = colorHex
        }
    }

    /// Menú de hoy («Hoy se come»). Sin datos de salud: solo franja, hora y título.
    public struct Meals: Codable, Equatable, Sendable {
        public struct Item: Codable, Equatable, Sendable, Identifiable {
            /// Clave de la franja (`breakfast`, `lunch`…).
            public let slot: String
            /// Hora local del hogar, `HH:mm`.
            public let time: String
            public let title: String
            public var id: String { "\(slot)-\(time)-\(title)" }

            public init(slot: String, time: String, title: String) {
                self.slot = slot
                self.time = time
                self.title = title
            }
        }

        /// Día al que pertenecen las casillas, `yyyy-MM-dd` en la zona del hogar.
        public let date: String
        /// Identificador de la zona horaria del hogar.
        public let timezone: String
        public let hasPlan: Bool
        /// Casillas de hoy ordenadas por hora.
        public let items: [Item]

        public init(date: String, timezone: String, hasPlan: Bool, items: [Item]) {
            self.date = date
            self.timezone = timezone
            self.hasPlan = hasPlan
            self.items = items
        }

        private var zone: TimeZone { TimeZone(identifier: timezone) ?? .current }

        /// Instante de inicio de una casilla en el día del menú; `nil` si la hora no es válida.
        public func start(of item: Item) -> Date? {
            let dayParts = date.split(separator: "-").compactMap { Int($0) }
            let timeParts = item.time.split(separator: ":").compactMap { Int($0) }
            guard dayParts.count == 3, timeParts.count >= 2 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(
                year: dayParts[0], month: dayParts[1], day: dayParts[2], hour: timeParts[0], minute: timeParts[1]
            ))
        }

        /// ¿El menú es del día de `now` en la zona del hogar?
        public func isCurrentDay(at now: Date) -> Bool {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return false }
            return date == String(format: "%04d-%02d-%02d", year, month, day)
        }

        /// Casillas visibles (hay menú aceptado y casillas) solo si el menú es del día de `now`.
        public func visibleItems(at now: Date) -> [Item] {
            hasPlan && isCurrentDay(at: now) ? items : []
        }

        /// Franja actual: la primera casilla que no ha empezado antes de `now` (mismo criterio que la
        /// pantalla de pared); si ya pasaron todas, `nil`.
        public func currentIndex(at now: Date) -> Int? {
            let visible = visibleItems(at: now)
            return visible.firstIndex { item in start(of: item).map { $0 >= now } ?? false }
        }

        /// Instantes de inicio de casilla posteriores a `now` (donde cambia lo que se destaca).
        public func boundaries(after now: Date) -> [Date] {
            Array(Set(items.compactMap { start(of: $0) }.filter { $0 > now })).sorted()
        }
    }

    public var generatedAt: Date
    /// Medianoche local del día al que pertenecen las rutinas y eventos.
    public var dayStart: Date
    public var homeName: String?
    /// Hay sesión iniciada en la app.
    public var signedIn: Bool
    /// Rutinas de hoy ordenadas por hora (sin hora al final).
    public var routines: [Routine]
    public var events: [Event]
    public var pendingTaskCount: Int
    public var tasks: [TaskItem]
    /// Menú de hoy; `nil` si no hay dato (sin permiso, sin red al construir o snapshot antiguo).
    public var meals: Meals?

    public init(
        generatedAt: Date, dayStart: Date, homeName: String? = nil, signedIn: Bool = true,
        routines: [Routine] = [], events: [Event] = [], pendingTaskCount: Int = 0, tasks: [TaskItem] = [],
        meals: Meals? = nil
    ) {
        self.generatedAt = generatedAt
        self.dayStart = dayStart
        self.homeName = homeName
        self.signedIn = signedIn
        self.routines = routines
        self.events = events
        self.pendingTaskCount = pendingTaskCount
        self.tasks = tasks
        self.meals = meals
    }

    // `meals` es posterior a la primera versión del fichero: un snapshot viejo se sigue leyendo.
    private enum CodingKeys: String, CodingKey {
        case generatedAt, dayStart, homeName, signedIn, routines, events, pendingTaskCount, tasks, meals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        dayStart = try container.decode(Date.self, forKey: .dayStart)
        homeName = try container.decodeIfPresent(String.self, forKey: .homeName)
        signedIn = try container.decode(Bool.self, forKey: .signedIn)
        routines = try container.decode([Routine].self, forKey: .routines)
        events = try container.decode([Event].self, forKey: .events)
        pendingTaskCount = try container.decode(Int.self, forKey: .pendingTaskCount)
        tasks = try container.decode([TaskItem].self, forKey: .tasks)
        meals = try container.decodeIfPresent(Meals.self, forKey: .meals)
    }

    /// Foto vacía de «sin sesión».
    public static func signedOut(now: Date = Date()) -> HomitaSnapshot {
        HomitaSnapshot(generatedAt: now, dayStart: now, signedIn: false)
    }

    /// ¿Pertenece a otro día que `now`? Entonces las rutinas ya no valen.
    public func isStale(at now: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(dayStart, inSameDayAs: now)
    }

    /// Solo las rutinas asignadas a la persona de esta cuenta. La Live Activity se calcula sobre
    /// esta vista: sin asignación (o sin persona vinculada) no hay nada que mostrar.
    public var assignedToMeOnly: HomitaSnapshot {
        var scoped = self
        scoped.routines = routines.filter(\.assignedToMe)
        return scoped
    }

    // MARK: - Lógica de «ahora / siguiente» (la usan widgets y Live Activity)

    /// Rutinas con hora, ordenadas por inicio.
    public var timedRoutines: [Routine] {
        routines.filter { $0.start != nil }.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    /// Rutinas hechas hoy a la hora `now`.
    public func doneCount(at now: Date) -> Int {
        routines.filter { $0.phase(at: now) == .done }.count
    }

    /// Rutina que se destaca: la que está en curso (la que empezó más tarde); si no, la próxima.
    public func focusRoutine(at now: Date) -> Routine? {
        let current = timedRoutines.filter { $0.phase(at: now) == .now }
        if let latest = current.max(by: { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }) { return latest }
        return timedRoutines.first { ($0.start ?? .distantPast) > now }
    }

    /// Rutina con hora posterior a `routine` (para «Siguiente»).
    public func routine(after routine: Routine, at now: Date) -> Routine? {
        timedRoutines.first { ($0.start ?? .distantPast) > max(now, routine.start ?? now) && $0.id != routine.id }
    }

    /// Instantes en los que cambia lo que se muestra (inicio − 1 h, inicio, inicio + 1 h) tras `now`.
    public func boundaries(after now: Date) -> [Date] {
        var result = Set<Date>()
        for routine in timedRoutines {
            guard let start = routine.start else { continue }
            for date in [start.addingTimeInterval(-HomitaShared.routineSoonWindow), start,
                         start.addingTimeInterval(HomitaShared.routineWindow)] where date > now {
                result.insert(date)
            }
        }
        return result.sorted()
    }
}

/// Lectura y escritura del snapshot en la carpeta del App Group.
public struct SnapshotStore {
    public static let fileName = "homita-snapshot.json"

    private let directory: URL?

    /// `directory` = carpeta del App Group por defecto; `nil` si no hay grupo (no se guarda nada).
    public init(directory: URL? = HomitaShared.containerURL) {
        self.directory = directory
    }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Último snapshot; `nil` si no hay o está dañado.
    public func load() -> HomitaSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.makeDecoder().decode(HomitaSnapshot.self, from: data)
    }

    @discardableResult
    public func save(_ snapshot: HomitaSnapshot) -> Bool {
        guard let fileURL, let data = try? Self.makeEncoder().encode(snapshot) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    public func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
