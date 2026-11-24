import Foundation

/// Estado de Menú › Compra: la lista del hogar por sección. Marcar es optimista (se revierte si el
/// servidor falla); las filas de origen menú que el servidor oculta (`cleared`) no llegan nunca. Si la
/// `revision` sube entre dos cargas (el menú cambió) se calcula el aviso «+a −r».
@Observable
public final class ShoppingStore {
    public private(set) var items: [ShoppingItem] = []
    public private(set) var revision = 0
    public private(set) var state: HomeAdminLoadState = .idle
    public private(set) var isWorking = false
    public var errorMessage: String?
    /// Aviso de cambios del menú sobre la lista («+2 −1»); la vista lo descarta con `dismissChanges()`.
    public private(set) var changeNotice: String?
    /// Sugerencias del catálogo para el alta a mano.
    public private(set) var suggestions: [Food] = []

    private let repo: ShoppingRepository
    private let searchFoods: (String) async throws -> [Food]
    private let activeHomeId: () -> String?

    public init(repo: ShoppingRepository, searchFoods: @escaping (String) async throws -> [Food] = { _ in [] },
                activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.searchFoods = searchFoods
        self.activeHomeId = activeHomeId
    }

    // MARK: Derivados

    /// Artículos por sección en orden de pasillo; dentro de cada sección, primero lo pendiente.
    public var sections: [(section: String, items: [ShoppingItem])] {
        let grouped = Dictionary(grouping: items, by: \.section)
        let known = ShoppingFormat.sectionOrder.filter { grouped[$0] != nil }
        let extra = grouped.keys.filter { !ShoppingFormat.sectionOrder.contains($0) }.sorted()
        return (known + extra).map { section in
            (section, (grouped[section] ?? []).sorted {
                ($0.isPending ? 0 : 1, $0.label.lowercased(), $0.id) < ($1.isPending ? 0 : 1, $1.label.lowercased(), $1.id)
            })
        }
    }

    public var pendingCount: Int { items.filter(\.isPending).count }
    public var checkedCount: Int { items.filter(\.isChecked).count }
    public var isEmpty: Bool { items.isEmpty }

    // MARK: Carga

    public func load() async {
        let requested = activeHomeId()
        if state != .loaded { state = .loading }
        do {
            let list = try await repo.list()
            guard activeHomeId() == requested else { return }
            apply(list)
            state = .loaded
        } catch {
            guard activeHomeId() == requested else { return }
            if state != .loaded { state = .failed(homeAdminMessage(error)) } else { errorMessage = homeAdminMessage(error) }
        }
    }

    private func apply(_ list: ShoppingList) {
        let hadList = state == .loaded
        if hadList, list.revision > revision {
            let diff = Self.diff(old: items, new: list.items)
            changeNotice = diff.isEmpty ? nil : "El menú ha cambiado la lista: \(diff.summary)"
        }
        revision = list.revision
        items = list.items
    }

    /// Diferencia de artículos de origen menú entre dos cargas (para el aviso).
    static func diff(old: [ShoppingItem], new: [ShoppingItem]) -> ShoppingSyncResult {
        let oldMenu = Dictionary(old.filter { $0.origin == ShoppingOrigin.menu }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newMenu = Dictionary(new.filter { $0.origin == ShoppingOrigin.menu }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let added = newMenu.keys.filter { oldMenu[$0] == nil }.count
        let removed = oldMenu.keys.filter { newMenu[$0] == nil }.count
        let updated = newMenu.filter { id, item in oldMenu[id].map { $0.quantity != item.quantity || $0.unit != item.unit } ?? false }.count
        return ShoppingSyncResult(added: added, updated: updated, removed: removed)
    }

    public func dismissChanges() { changeNotice = nil }

    /// Aviso con el resultado de una sincronización conocida (p. ej. al aceptar el menú).
    public func noteSync(_ result: ShoppingSyncResult) {
        changeNotice = result.isEmpty ? nil : "Lista de la compra actualizada: \(result.summary)"
    }

    // MARK: Escrituras

    /// Tocar marca o desmarca; un «ya lo tengo» vuelve a pendiente.
    public func toggle(_ item: ShoppingItem) async {
        await setState(item, to: item.isPending ? ShoppingState.checked : ShoppingState.pending)
    }

    /// «Ya lo tengo» (o lo deshace si ya estaba).
    public func haveIt(_ item: ShoppingItem) async {
        await setState(item, to: item.isSkipped ? ShoppingState.pending : ShoppingState.skipped)
    }

    private func setState(_ item: ShoppingItem, to newState: String) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let requested = activeHomeId()
        let before = items[index]
        items[index].state = newState
        do {
            let updated = try await repo.setState(id: item.id, state: newState)
            guard activeHomeId() == requested else { return }
            replace(updated)
        } catch {
            guard activeHomeId() == requested else { return }
            replace(before)
            errorMessage = homeAdminMessage(error)
            if let api = error as? APIError, api.isNotFound { await load() }
        }
    }

    /// Edita la cantidad: el servidor deja de sincronizarla con el menú.
    public func updateQuantity(_ item: ShoppingItem, quantity: Double, unit: String? = nil) async {
        await run { [self] in
            replace(try await repo.updateQuantity(id: item.id, quantity: quantity, unit: unit))
        }
    }

    /// Alta a mano; con `food` toma sección y nombre del catálogo.
    @discardableResult
    public func add(label: String, quantity: Double? = nil, unit: String = "ud", food: Food? = nil) async -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || food != nil else { return false }
        return await run { [self] in
            let created = try await repo.create(label: trimmed.isEmpty ? nil : trimmed, quantity: quantity, unit: unit,
                                                section: food?.section, foodId: food?.id)
            items.append(created)
            suggestions = []
        }
    }

    public func delete(_ item: ShoppingItem) async {
        await run { [self] in
            try await repo.delete(id: item.id)
            items.removeAll { $0.id == item.id }
        }
    }

    /// Vacía los comprados.
    public func clearChecked() async {
        await run { [self] in
            try await repo.clearChecked()
            items.removeAll { $0.isChecked }
        }
    }

    /// Autocompletar del catálogo mientras se escribe (mínimo 2 letras).
    public func suggest(_ query: String) async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { suggestions = []; return }
        suggestions = (try? await searchFoods(text)) ?? []
    }

    private func replace(_ item: ShoppingItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    }

    @discardableResult
    private func run(_ body: () async throws -> Void) async -> Bool {
        let requested = activeHomeId()
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
            errorMessage = nil
            return true
        } catch {
            guard activeHomeId() == requested else { return false }
            errorMessage = homeAdminMessage(error)
            return false
        }
    }
}
