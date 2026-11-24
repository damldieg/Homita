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

    enum CodingKeys: String, CodingKey {
        case weekStartDay = "week_start_day", shoppingDay = "shopping_day"
        case cookMinutesWeekday = "cook_minutes_weekday", cookMinutesWeekend = "cook_minutes_weekend"
        case cookSkill = "cook_skill", equipment, freezerSpace = "freezer_space"
        case repeatPolicy = "repeat_policy", leftovers, dessert, budgetWeekly = "budget_weekly"
        case taskListId = "task_list_id", groupBySection = "group_by_section"
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

    public init(shoppingDay: Int? = nil, weekStartDay: Int? = nil, cookMinutesWeekday: Int? = nil,
                cookMinutesWeekend: Int? = nil, cookSkill: String? = nil, equipment: [String]? = nil,
                freezerSpace: String? = nil, repeatPolicy: String? = nil, leftovers: String? = nil,
                dessert: String? = nil, budgetWeekly: Double? = nil, groupBySection: Bool? = nil) {
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
    }

    enum CodingKeys: String, CodingKey {
        case shoppingDay = "shopping_day", weekStartDay = "week_start_day"
        case cookMinutesWeekday = "cook_minutes_weekday", cookMinutesWeekend = "cook_minutes_weekend"
        case cookSkill = "cook_skill", equipment, freezerSpace = "freezer_space"
        case repeatPolicy = "repeat_policy", leftovers, dessert, budgetWeekly = "budget_weekly"
        case groupBySection = "group_by_section"
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
