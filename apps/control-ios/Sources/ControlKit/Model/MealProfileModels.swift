import Foundation

/// Perfil de hogar del planificador de comidas (`GET meal/profile`, 0043). B3/B4 (intolerancias y
/// condiciones médicas) quedan fuera del piloto: el contrato no los lleva.
public struct MealAllergy: Codable, Equatable, Sendable {
    public var allergen: String
    public var severity: String
    public var note: String?

    public init(allergen: String, severity: String, note: String? = nil) {
        self.allergen = allergen
        self.severity = severity
        self.note = note
    }
}

public struct MealSlot: Codable, Equatable, Sendable, Identifiable {
    public var slot: String
    public var enabled: Bool
    /// Hora local del hogar, `HH:mm`.
    public var time: String
    public var id: String { slot }

    public init(slot: String, enabled: Bool, time: String) {
        self.slot = slot
        self.enabled = enabled
        self.time = time
    }
}

/// Ajustes del hogar (D3, E, F, G). `preferences` (jsonb) no se decodifica: la UI no lo usa aún.
public struct MealHomeSettings: Codable, Equatable, Sendable {
    public var weekStartDay: Int
    public var shoppingDay: Int
    public var cookMinutesWeekday: Int?
    public var cookMinutesWeekend: Int?
    public var cookSkill: String?
    public var equipment: [String]
    public var freezerSpace: String?
    public var repeatPolicy: String?
    public var leftovers: String?
    public var dessert: String?
    public var budgetWeekly: Double?
    public var taskListId: Int?
    public var groupBySection: Bool
    /// Países de los que el hogar quiere recetas (ISO 3166-1 alfa-2, 0046); vacío si no eligió o el
    /// servidor aún no lo envía.
    public var countries: [String]

    enum CodingKeys: String, CodingKey {
        case weekStartDay = "week_start_day", shoppingDay = "shopping_day"
        case cookMinutesWeekday = "cook_minutes_weekday", cookMinutesWeekend = "cook_minutes_weekend"
        case cookSkill = "cook_skill", equipment, freezerSpace = "freezer_space"
        case repeatPolicy = "repeat_policy", leftovers, dessert, budgetWeekly = "budget_weekly"
        case taskListId = "task_list_id", groupBySection = "group_by_section", countries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStartDay = try c.decode(Int.self, forKey: .weekStartDay)
        shoppingDay = try c.decode(Int.self, forKey: .shoppingDay)
        cookMinutesWeekday = try c.decodeIfPresent(Int.self, forKey: .cookMinutesWeekday)
        cookMinutesWeekend = try c.decodeIfPresent(Int.self, forKey: .cookMinutesWeekend)
        cookSkill = try c.decodeIfPresent(String.self, forKey: .cookSkill)
        equipment = try c.decode([String].self, forKey: .equipment)
        freezerSpace = try c.decodeIfPresent(String.self, forKey: .freezerSpace)
        repeatPolicy = try c.decodeIfPresent(String.self, forKey: .repeatPolicy)
        leftovers = try c.decodeIfPresent(String.self, forKey: .leftovers)
        dessert = try c.decodeIfPresent(String.self, forKey: .dessert)
        budgetWeekly = try c.decodeIfPresent(Double.self, forKey: .budgetWeekly)
        taskListId = try c.decodeIfPresent(Int.self, forKey: .taskListId)
        groupBySection = try c.decode(Bool.self, forKey: .groupBySection)
        countries = try c.decodeIfPresent([String].self, forKey: .countries) ?? []
    }
}

/// Lista cerrada de países del perfil de hogar (misma que `fn_meal_countries_valid`, 0046), con nombre en
/// español y bandera. Si el servidor devuelve un código que no está aquí, se muestra el código tal cual.
public enum MealCountries {
    public static let codes: [String] = [
        "ES", "AR", "MX", "CO", "CL", "PE", "UY", "VE", "EC", "BO", "PY", "CR", "PA", "DO", "GT", "HN", "SV", "NI",
        "CU", "PR", "IT", "FR", "DE", "PT", "GB", "US", "MA", "TR", "CN", "JP", "IN", "MY", "PH", "GR", "NL", "BE",
        "SE", "PL", "RO", "UA", "RU", "LB", "SY", "EG", "DZ", "TN", "ET", "NG", "SN", "CI", "BR",
    ]

    /// Nombre en español («Argentina»); el código si el sistema no lo conoce.
    public static func name(_ code: String) -> String {
        Locale(identifier: "es_ES").localizedString(forRegionCode: code) ?? code
    }

    /// Bandera como emoji (letras indicadoras regionales); vacío si el código no son dos letras A–Z.
    public static func flag(_ code: String) -> String {
        guard code.count == 2, code.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }

    /// «🇦🇷 Argentina».
    public static func label(_ code: String) -> String {
        let flag = flag(code)
        return flag.isEmpty ? name(code) : "\(flag) \(name(code))"
    }

    /// Todos los países ordenados por nombre (orden de España, sin acentos ni mayúsculas).
    public static var sorted: [String] {
        codes.sorted { name($0).compare(name($1), options: [.caseInsensitive, .diacriticInsensitive],
                                        locale: Locale(identifier: "es_ES")) == .orderedAscending }
    }
}

/// Ficha de una persona que come (A2, A3, B1+B2, B5, B6, C1–C4).
public struct MealMember: Codable, Equatable, Sendable, Identifiable {
    public var homeMemberId: Int
    public var name: String
    public var kind: String
    public var linked: Bool
    public var isMe: Bool
    public var ageBand: String
    public var portionSize: String?
    public var allergiesAnswered: Bool
    public var allergies: [MealAllergy]
    public var diet: String
    public var dietNote: String?
    public var goals: [String]
    public var dislikes: [String]
    public var favorites: [String]
    public var quirks: String?
    public var spice: Int?
    public var id: Int { homeMemberId }

    enum CodingKeys: String, CodingKey {
        case homeMemberId = "home_member_id", name, kind, linked, isMe = "is_me"
        case ageBand = "age_band", portionSize = "portion_size"
        case allergiesAnswered = "allergies_answered", allergies, diet, dietNote = "diet_note"
        case goals, dislikes, favorites, quirks, spice
    }
}

public struct MealScheduleEntry: Codable, Equatable, Sendable {
    public var homeMemberId: Int
    public var weekday: Int
    public var slot: String
    public var status: String

    public init(homeMemberId: Int, weekday: Int, slot: String, status: String) {
        self.homeMemberId = homeMemberId
        self.weekday = weekday
        self.slot = slot
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case homeMemberId = "home_member_id", weekday, slot, status
    }
}

public struct MealProfile: Codable, Equatable, Sendable {
    public var homeId: Int
    public var timezone: String
    /// Tiene `menu.profile.edit` (edita todo); si no, solo su bloque C.
    public var canEdit: Bool
    public var profile: MealHomeSettings
    public var slots: [MealSlot]
    public var members: [MealMember]
    /// A1: personas que pueden comer (miembros activos sin mascotas). Llega con `menu.view`, sin
    /// depender de `home.view` (un adulto no admin no puede llamar a `GET home/member`).
    public var candidates: [HomeMember]
    public var schedule: [MealScheduleEntry]

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id", timezone, canEdit = "can_edit", profile, slots, members, candidates, schedule
    }
}

/// Cambios del hogar; los nil no se envían.
public struct MealHomeUpdate: Encodable, Equatable, Sendable {
    public var shoppingDay: Int?
    public var weekStartDay: Int?
    public var cookMinutesWeekday: Int?
    public var cookMinutesWeekend: Int?
    public var cookSkill: String?
    public var equipment: [String]?
    public var freezerSpace: String?
    public var repeatPolicy: String?
    public var leftovers: String?
    public var dessert: String?
    public var budgetWeekly: Double?
    public var groupBySection: Bool?
    /// Lista completa de países (reemplaza la anterior); `[]` la vacía.
    public var countries: [String]?

    public init(shoppingDay: Int? = nil, weekStartDay: Int? = nil, cookMinutesWeekday: Int? = nil,
                cookMinutesWeekend: Int? = nil, cookSkill: String? = nil, equipment: [String]? = nil,
                freezerSpace: String? = nil, repeatPolicy: String? = nil, leftovers: String? = nil,
                dessert: String? = nil, budgetWeekly: Double? = nil, groupBySection: Bool? = nil,
                countries: [String]? = nil) {
        self.shoppingDay = shoppingDay
        self.weekStartDay = weekStartDay
        self.cookMinutesWeekday = cookMinutesWeekday
        self.cookMinutesWeekend = cookMinutesWeekend
        self.cookSkill = cookSkill
        self.equipment = equipment
        self.freezerSpace = freezerSpace
        self.repeatPolicy = repeatPolicy
        self.leftovers = leftovers
        self.dessert = dessert
        self.budgetWeekly = budgetWeekly
        self.groupBySection = groupBySection
        self.countries = countries
    }

    enum CodingKeys: String, CodingKey {
        case shoppingDay = "shopping_day", weekStartDay = "week_start_day"
        case cookMinutesWeekday = "cook_minutes_weekday", cookMinutesWeekend = "cook_minutes_weekend"
        case cookSkill = "cook_skill", equipment, freezerSpace = "freezer_space"
        case repeatPolicy = "repeat_policy", leftovers, dessert, budgetWeekly = "budget_weekly"
        case groupBySection = "group_by_section", countries
    }
}

/// Cambios de la ficha de una persona; los nil no se envían. `eats: false` borra la ficha.
public struct MealMemberUpdate: Encodable, Equatable, Sendable {
    public var homeMemberId: Int
    public var eats: Bool?
    public var ageBand: String?
    public var portionSize: String?
    public var allergiesAnswered: Bool?
    public var allergies: [MealAllergy]?
    public var diet: String?
    public var dietNote: String?
    public var goals: [String]?
    public var dislikes: [String]?
    public var favorites: [String]?
    public var quirks: String?
    public var spice: Int?

    public init(homeMemberId: Int, eats: Bool? = nil, ageBand: String? = nil, portionSize: String? = nil,
                allergiesAnswered: Bool? = nil, allergies: [MealAllergy]? = nil, diet: String? = nil,
                dietNote: String? = nil, goals: [String]? = nil, dislikes: [String]? = nil,
                favorites: [String]? = nil, quirks: String? = nil, spice: Int? = nil) {
        self.homeMemberId = homeMemberId
        self.eats = eats
        self.ageBand = ageBand
        self.portionSize = portionSize
        self.allergiesAnswered = allergiesAnswered
        self.allergies = allergies
        self.diet = diet
        self.dietNote = dietNote
        self.goals = goals
        self.dislikes = dislikes
        self.favorites = favorites
        self.quirks = quirks
        self.spice = spice
    }

    enum CodingKeys: String, CodingKey {
        case homeMemberId = "home_member_id", eats, ageBand = "age_band", portionSize = "portion_size"
        case allergiesAnswered = "allergies_answered", allergies, diet, dietNote = "diet_note"
        case goals, dislikes, favorites, quirks, spice
    }

    /// Claves del bloque C (gustos): lo único que una persona sin `menu.profile.edit` puede enviar.
    public var onlyTasteBlock: Bool {
        eats == nil && ageBand == nil && portionSize == nil && allergiesAnswered == nil && allergies == nil
            && diet == nil && dietNote == nil && goals == nil
    }
}

struct MealSlotsBody: Encodable { let slots: [MealSlot] }
struct MealScheduleBody: Encodable { let entries: [MealScheduleEntry] }
