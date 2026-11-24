import Foundation

/// Estado de la pestaña Menú › Semana: perfil (franjas y horario), plan de la semana visible, copia
/// de trabajo con las ediciones locales y avisos del check. Las ediciones solo viajan en `save()`
/// con la `revision` vigente; un 409 relee el plan, descarta lo local y avisa.
@Observable
public final class MealsStore {
    public private(set) var profile: MealProfile?
    /// Plan del servidor (nil si la semana no tiene).
    public private(set) var plan: MealPlan?
    /// Copia de trabajo: lo que pinta la rejilla. Difiere de `plan.items` mientras hay ediciones.
    public private(set) var items: [MealPlanItem] = []
    public private(set) var issues: [MealIssue] = []
    public private(set) var weekStart: String
    public private(set) var state: HomeAdminLoadState = .idle
    public private(set) var isWorking = false
    public var errorMessage: String?
    /// Aviso no bloqueante (p. ej. «el menú cambió, se ha recargado»).
    public var notice: String?
    /// Nº de eventos de calendario por día (`YYYY-MM-DD`); lo rellena la vista con lo ya cargado.
    public var eventCounts: [String: Int] = [:]

    private let meals: MealRepository
    private let events: EventRepository?
    private let activeHomeId: () -> String?
    private let now: () -> Date

    public init(meals: MealRepository, events: EventRepository? = nil, activeHomeId: @escaping () -> String?,
                now: @escaping () -> Date = Date.init) {
        self.meals = meals
        self.events = events
        self.activeHomeId = activeHomeId
        self.now = now
        weekStart = MealWeek.weekStart(containing: now(), weekStartDay: 1, timeZone: .current)
    }

    // MARK: Derivados

    public var timeZone: TimeZone { profile.flatMap { TimeZone(identifier: $0.timezone) } ?? .current }
    public var days: [String] { MealWeek.days(of: weekStart, timeZone: timeZone) }
    public var enabledSlots: [MealSlot] {
        (profile?.slots ?? []).filter(\.enabled).sorted {
            (MealSlotKind.order.firstIndex(of: $0.slot) ?? 99) < (MealSlotKind.order.firstIndex(of: $1.slot) ?? 99)
        }
    }
    public var canEdit: Bool { plan?.status != MealPlanStatus.archived }
    public var isDraft: Bool { plan == nil || plan?.status == MealPlanStatus.draft }
    public var isAccepted: Bool { plan?.status == MealPlanStatus.accepted }
    public var currentWeekStart: String {
        MealWeek.weekStart(containing: now(), weekStartDay: profile?.profile.weekStartDay ?? 1, timeZone: timeZone)
    }

    /// Hay cambios locales sin guardar.
    public var isDirty: Bool { !pendingChanges().items.isEmpty || !pendingChanges().deleteIds.isEmpty }

    public func items(day: String, slot: String) -> [MealPlanItem] {
        items.filter { $0.day == day && $0.slot == slot }.sorted { $0.position < $1.position }
    }

    /// `true` si la persona está fuera (`out`, `skip` o `lunchbox`) ese día y franja según el horario.
    public func isOut(memberId: Int, day: String, slot: String) -> Bool {
        guard let weekday = MealWeek.isoWeekday(day, timeZone: timeZone) else { return false }
        return profile?.schedule.contains {
            $0.homeMemberId == memberId && $0.weekday == weekday && $0.slot == slot && $0.status != "home"
        } ?? false
    }

    /// Avisos de una casilla guardada.
    public func issues(for item: MealPlanItem) -> [MealIssue] {
        guard let id = item.id else { return [] }
        return issues.filter { $0.itemId == id }
    }

    // MARK: Carga

    public func load() async {
        let requested = activeHomeId()
        state = .loading
        do {
            if profile == nil {
                let loaded = try await meals.profile()
                guard activeHomeId() == requested else { return }
                profile = loaded
                weekStart = currentWeekStart
            }
            try await loadPlan(requested: requested)
            state = .loaded
        } catch {
            guard activeHomeId() == requested else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    /// Recarga solo la semana visible (tras un 409 o al cambiar de semana).
    private func loadPlan(requested: String?) async throws {
        let loaded = try await meals.plan(weekStart: weekStart)
        guard activeHomeId() == requested else { return }
        apply(loaded)
        await refreshIssues()
        await loadEventCounts()
    }

    /// Eventos de calendario por día de la semana visible (best-effort: si falla, sin contadores).
    public func loadEventCounts() async {
        guard let events, let first = days.first, let last = days.last,
              let start = MealWeek.date(first, timeZone: timeZone), let end = MealWeek.date(last, timeZone: timeZone) else {
            eventCounts = [:]
            return
        }
        let calendar = MealWeek.calendar(timeZone)
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end).addingTimeInterval(86_399)
        let filters = EventFilters(
            startDate: LocalClock.epochString(for: from, timeZone: timeZone),
            endDate: LocalClock.epochString(for: to, timeZone: timeZone), routine: false, timezone: timeZone.identifier)
        guard let list = try? await events.index(filters) else { eventCounts = [:]; return }
        var counts: [String: Int] = [:]
        for event in list {
            let day = String(event.date_at.prefix(10))
            if days.contains(day) { counts[day, default: 0] += 1 }
        }
        eventCounts = counts
    }

    private func apply(_ loaded: MealPlan?) {
        plan = loaded
        items = loaded?.items ?? []
    }

    public func refreshIssues() async {
        guard let plan, !isDirty else { issues = []; return }
        issues = (try? await meals.check(planId: plan.id)) ?? []
    }

    public func shiftWeek(by weeks: Int) async {
        guard let next = MealWeek.addDays(weekStart, 7 * weeks, timeZone: timeZone) else { return }
        weekStart = next
        notice = nil
        await reloadWeek()
    }

    public func goToCurrentWeek() async {
        weekStart = currentWeekStart
        await reloadWeek()
    }

    private func reloadWeek() async {
        let requested = activeHomeId()
        state = .loading
        do {
            try await loadPlan(requested: requested)
            state = .loaded
        } catch {
            state = .failed(homeAdminMessage(error))
        }
    }

    // MARK: Edición local

    /// Añade una casilla nueva (sin `id`) al final de su día y franja.
    public func add(_ item: MealPlanItem) {
        var new = item
        new.id = nil
        new.position = (items(day: item.day, slot: item.slot).map(\.position).max() ?? -1) + 1
        items.append(new)
    }

    /// Reemplaza una casilla (por `id` o, si es nueva, por su clave).
    public func replace(_ item: MealPlanItem, with updated: MealPlanItem) {
        guard let index = items.firstIndex(where: { $0.key == item.key }) else { return }
        var next = updated
        next.id = item.id
        items[index] = next
    }

    public func remove(_ item: MealPlanItem) {
        items.removeAll { $0.key == item.key }
    }

    /// Copia las casillas de un día en otro: las del destino se sustituyen por clones sin `id`.
    public func copyDay(from source: String, to target: String) {
        guard source != target else { return }
        items.removeAll { $0.day == target }
        for item in items.filter({ $0.day == source }) {
            var clone = item
            clone.id = nil
            clone.day = target
            items.append(clone)
        }
    }

    public func discardChanges() {
        items = plan?.items ?? []
    }

    /// Casillas nuevas o distintas de la versión del servidor, y las que ya no están.
    func pendingChanges() -> (items: [MealPlanItem], deleteIds: [Int64]) {
        let server = plan?.items ?? []
        let byId = Dictionary(server.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
        let changed = items.filter { item in
            guard let id = item.id, let old = byId[id] else { return true }
            return old != item
        }
        let kept = Set(items.compactMap(\.id))
        let deleted = server.compactMap(\.id).filter { !kept.contains($0) }
        return (changed, deleted)
    }

    // MARK: Escrituras

    /// Guarda las ediciones con la revisión vigente. Devuelve `false` si no se guardó (error o 409).
    @discardableResult
    public func save() async -> Bool {
        let changes = pendingChanges()
        guard !changes.items.isEmpty || !changes.deleteIds.isEmpty else { return true }
        return await write {
            try await $0.saveItems(weekStart: self.weekStart, expectedRevision: self.plan?.revision ?? 0,
                                   items: changes.items, deleteIds: changes.deleteIds)
        }
    }

    /// Acepta el menú (guarda antes lo pendiente).
    public func accept() async {
        guard await save(), let plan else { return }
        await write { try await $0.accept(planId: plan.id, expectedRevision: plan.revision) }
    }

    /// Libera la semana para rehacerla.
    public func archive() async {
        guard let plan else { return }
        await write { try await $0.archive(planId: plan.id) }
        if self.plan?.status == MealPlanStatus.archived { apply(nil); issues = [] }
    }

    /// «Repetir semana pasada»: copia la semana anterior a la visible (que debe estar libre).
    public func repeatPreviousWeek() async {
        guard plan == nil, let previous = MealWeek.addDays(weekStart, -7, timeZone: timeZone) else { return }
        await write { try await $0.copyWeek(from: previous, to: self.weekStart) }
    }

    /// Ejecuta una escritura de plan: aplica el plan devuelto; 409 relee, descarta lo local y avisa.
    @discardableResult
    private func write(_ call: (MealRepository) async throws -> MealPlan) async -> Bool {
        let requested = activeHomeId()
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await call(meals)
            guard activeHomeId() == requested else { return false }
            apply(updated)
            errorMessage = nil
            await refreshIssues()
            return true
        } catch let error as APIError where error.isStaleRevision || error.isMealPlanExists {
            notice = error.userMessage
            do { try await loadPlan(requested: requested) } catch { errorMessage = homeAdminMessage(error) }
            return false
        } catch {
            errorMessage = homeAdminMessage(error)
            return false
        }
    }
}
