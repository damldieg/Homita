import Foundation

/// Opciones del formulario (valor del contrato → etiqueta) y reglas puras del perfil de comidas.
public enum MealRules {
    public static let allergens: [(String, String)] = [
        ("gluten", "Gluten"), ("crustaceans", "Crustáceos"), ("egg", "Huevo"), ("fish", "Pescado"),
        ("peanut", "Cacahuete"), ("soy", "Soja"), ("milk", "Leche"), ("tree_nuts", "Frutos de cáscara"),
        ("celery", "Apio"), ("mustard", "Mostaza"), ("sesame", "Sésamo"), ("sulphites", "Sulfitos"),
        ("lupin", "Altramuces"), ("molluscs", "Moluscos"), ("other", "Otro"),
    ]
    public static let severities: [(String, String)] = [
        ("no_traces", "Ni trazas"), ("avoid_ingredient", "Evitar el ingrediente"),
    ]
    public static let diets: [(String, String)] = [
        ("omnivore", "Omnívora"), ("flexitarian", "Flexitariana"), ("pescatarian", "Pescetariana"),
        ("vegetarian", "Vegetariana"), ("vegan", "Vegana"), ("no_pork", "Sin cerdo"), ("halal", "Halal"),
        ("kosher", "Kosher"), ("other", "Otra"),
    ]
    public static let ageBands: [(String, String)] = [
        ("0-1", "0–1 años"), ("1-3", "1–3 años"), ("4-12", "4–12 años"), ("13-17", "13–17 años"),
        ("adult", "Adulto"), ("65+", "65 o más"),
    ]
    public static let slots: [(String, String)] = [
        ("breakfast", "Desayuno"), ("midmorning", "Media mañana"), ("lunch", "Comida"),
        ("snack", "Merienda"), ("dinner", "Cena"),
    ]
    /// Lunes = 1 … domingo = 7 (ISO, como el contrato).
    public static let weekdays: [(Int, String)] = [
        (1, "Lunes"), (2, "Martes"), (3, "Miércoles"), (4, "Jueves"), (5, "Viernes"), (6, "Sábado"), (7, "Domingo"),
    ]
    public static let cookMinutes: [(Int, String)] = [(15, "15 min"), (30, "30 min"), (45, "45 min"), (60, "1 h o más")]
    public static let skills: [(String, String)] = [("basic", "Básico"), ("medium", "Medio"), ("advanced", "Avanzado")]
    public static let equipment: [(String, String)] = [
        ("oven", "Horno"), ("microwave", "Microondas"), ("induction", "Inducción"), ("gas", "Gas"),
        ("stove", "Fuego"), ("robot", "Robot de cocina"), ("pressure_cooker", "Olla rápida"),
        ("air_fryer", "Freidora de aire"), ("slow_cooker", "Olla lenta"), ("griddle", "Plancha"),
        ("blender", "Batidora"), ("barbecue", "Barbacoa"),
    ]
    public static let freezer: [(String, String)] = [("little", "Poco"), ("normal", "Normal"), ("lots", "Mucho")]
    public static let repeatPolicies: [(String, String)] = [
        ("never_2_weeks", "Nunca en 2 semanas"), ("once_week", "1 vez por semana"), ("any", "Nos da igual"),
    ]
    public static let leftovers: [(String, String)] = [("use", "Las aprovechamos"), ("no", "No")]
    public static let desserts: [(String, String)] = [
        ("fruit", "Fruta"), ("dairy", "Lácteo"), ("sweet_weekend", "Dulce los findes"), ("none", "Nada"),
    ]
    public static let goals: [(String, String)] = [
        ("more_veg", "Más verdura"), ("less_red_meat", "Menos carne roja"),
        ("less_ultraprocessed", "Menos ultraprocesados"), ("lose_weight", "Perder peso"),
        ("more_protein", "Más proteína"),
    ]
    public static let spiceLevels: [(Int, String)] = [(0, "Nada"), (1, "Suave"), (2, "Medio"), (3, "Mucho")]

    public static func label<T: Equatable>(_ value: T?, in options: [(T, String)]) -> String? {
        guard let value else { return nil }
        return options.first { $0.0 == value }?.1
    }

    /// A1: quién puede comer en casa = miembros activos que no son mascotas (la lista llega en `GET meal/profile`).
    public static func eaterCandidates(_ members: [HomeMember]) -> [HomeMember] {
        members.filter { $0.kind != MemberKind.pet.rawValue && $0.status == MemberStatus.active.rawValue }
    }

    /// A2 por defecto según el tipo de miembro.
    public static func defaultAgeBand(kind: String) -> String {
        kind == MemberKind.child.rawValue ? "4-12" : "adult"
    }

    /// El arranque está completo cuando alguien come, todos tienen B1 respondida (vale «ninguna») y hay
    /// al menos una franja activa. El resto de preguntas son opcionales («ahora no»).
    public static func startComplete(_ profile: MealProfile) -> Bool {
        !profile.members.isEmpty
            && profile.members.allSatisfy(\.allergiesAnswered)
            && profile.slots.contains(where: \.enabled)
    }

    /// D2: por día, qué franjas se comen fuera. Todas las personas, `out` en las franjas que marca el modo;
    /// las filas que estaban `out` y dejan de estarlo vuelven a `home`. Solo se emiten las filas que cambian.
    /// Los días sin modo cuentan como `.none`.
    public static func outSchedule(modes: [Int: OutMode], eaters: [Int], slots: [MealSlot],
                                   current: [MealScheduleEntry]) -> [MealScheduleEntry] {
        let active = slots.filter(\.enabled).map(\.slot)
        var entries: [MealScheduleEntry] = []
        for member in eaters {
            for day in 1...7 {
                let wanted = (modes[day] ?? .none).slots(active: active)
                let outNow = Set(current.filter {
                    $0.homeMemberId == member && $0.weekday == day && $0.status == "out"
                }.map(\.slot))
                entries += active.filter { wanted.contains($0) && !outNow.contains($0) }
                    .map { MealScheduleEntry(homeMemberId: member, weekday: day, slot: $0, status: "out") }
                entries += current.filter {
                    $0.homeMemberId == member && $0.weekday == day && $0.status == "out" && !wanted.contains($0.slot)
                }.map { MealScheduleEntry(homeMemberId: member, weekday: day, slot: $0.slot, status: "home") }
            }
        }
        return entries
    }

    /// Modo de cada día para pintar D2: una franja cuenta como fuera si todas las personas están `out` en ella.
    /// Los patrones no representables (p. ej. solo desayuno fuera) se muestran como `.none`.
    public static func outModes(_ profile: MealProfile) -> [Int: OutMode] {
        let active = profile.slots.filter(\.enabled).map(\.slot)
        guard !profile.members.isEmpty, !active.isEmpty else { return [:] }
        func isOut(_ day: Int, _ slot: String) -> Bool {
            profile.members.allSatisfy { member in
                profile.schedule.contains {
                    $0.homeMemberId == member.homeMemberId && $0.weekday == day && $0.slot == slot && $0.status == "out"
                }
            }
        }
        var result: [Int: OutMode] = [:]
        for day in 1...7 {
            let out = Set(active.filter { isOut(day, $0) })
            if out.count == active.count { result[day] = .full }
            else if out == ["lunch"] { result[day] = .lunch }
            else if out == ["dinner"] { result[day] = .dinner }
        }
        return result
    }

    /// `HH:mm` ↔ minutos desde medianoche para el selector de hora; nil si no es válida.
    public static func minutes(fromTime time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else {
            return nil
        }
        return h * 60 + m
    }

    public static func time(fromMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

/// D2: qué se come fuera un día concreto.
public enum OutMode: CaseIterable, Equatable, Sendable {
    case none, full, lunch, dinner

    public var label: String {
        switch self {
        case .none: return "Ninguno"
        case .full: return "Día completo"
        case .lunch: return "Solo comida"
        case .dinner: return "Solo cena"
        }
    }

    /// Franjas `out` de este modo dadas las franjas activas.
    func slots(active: [String]) -> Set<String> {
        switch self {
        case .none: return []
        case .full: return Set(active)
        case .lunch: return active.contains("lunch") ? ["lunch"] : []
        case .dinner: return active.contains("dinner") ? ["dinner"] : []
        }
    }
}
