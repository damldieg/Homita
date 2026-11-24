import Foundation

/// Estado de Ajustes › Perfil de hogar: perfil del servidor, lista de comensales posibles (A1, viene en
/// `GET meal/profile` bajo `menu.view`; no usa `GET home/member`, que exige `home.view`) y escrituras. Tras cada escritura recarga del servidor.
@Observable
public final class MealProfileStore {
    public private(set) var profile: MealProfile?
    public private(set) var candidates: [HomeMember] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?

    private let meals: MealRepository
    private let activeHomeId: () -> String?

    public init(meals: MealRepository, activeHomeId: @escaping () -> String?) {
        self.meals = meals
        self.activeHomeId = activeHomeId
    }

    public var needsStart: Bool { profile.map { !MealRules.startComplete($0) } ?? false }

    public func load() async {
        let requested = activeHomeId()
        state = .loading
        do {
            let loaded = try await meals.profile()
            guard activeHomeId() == requested else { return }
            profile = loaded
            candidates = MealRules.eaterCandidates(loaded.candidates)
            state = .loaded
        } catch {
            guard activeHomeId() == requested else { return }
            state = .failed((error as? APIError)?.mealViewMessage ?? error.localizedDescription)
        }
    }

    /// Ficha del miembro si come.
    public func member(_ id: Int) -> MealMember? { profile?.members.first { $0.homeMemberId == id } }

    /// A1: marca o desmarca que una persona come; al marcar crea la ficha con la franja de edad por defecto.
    public func setEats(_ member: HomeMember, _ eats: Bool) async {
        if eats {
            await run { try await $0.updateMember(MealMemberUpdate(
                homeMemberId: member.id, ageBand: MealRules.defaultAgeBand(kind: member.kind))) }
        } else {
            await run { try await $0.updateMember(MealMemberUpdate(homeMemberId: member.id, eats: false)) }
        }
    }

    public func updateMember(_ update: MealMemberUpdate) async {
        await run { try await $0.updateMember(update) }
    }

    public func updateHome(_ update: MealHomeUpdate) async {
        await run { try await $0.updateHome(update) }
    }

    public func setSlots(_ slots: [MealSlot]) async {
        await run { try await $0.setSlots(slots) }
    }

    /// D2: modo «fuera» de cada día (día completo, solo comida, solo cena, ninguno).
    public func setOutModes(_ modes: [Int: OutMode]) async {
        guard let profile else { return }
        let entries = MealRules.outSchedule(modes: modes, eaters: profile.members.map(\.homeMemberId),
                                            slots: profile.slots, current: profile.schedule)
        guard !entries.isEmpty else { return }
        await run { try await $0.setSchedule(entries) }
    }

    private func run(_ write: (MealRepository) async throws -> Void) async {
        do {
            try await write(meals)
            await load()
        } catch {
            errorMessage = homeAdminMessage(error)
        }
    }
}
