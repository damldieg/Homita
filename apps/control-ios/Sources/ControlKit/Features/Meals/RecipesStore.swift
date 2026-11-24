import Foundation

/// Lista de recetas del hogar con búsqueda y filtros (franja y tiempo máximo). La usan la pestaña
/// Recetas y el selector de receta de la casilla.
@Observable
public final class RecipesStore {
    public private(set) var recipes: [RecipeSummary] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?
    public var query = ""
    public var slot: String?
    public var maxMinutes: Int?

    private let repo: RecipeRepository
    private let activeHomeId: () -> String?

    public init(repo: RecipeRepository, activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.activeHomeId = activeHomeId
    }

    public func load() async {
        let requested = activeHomeId()
        state = .loading
        do {
            let list = try await repo.list(query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                           slot: slot, maxMinutes: maxMinutes)
            guard activeHomeId() == requested else { return }
            recipes = list
            state = .loaded
        } catch {
            guard activeHomeId() == requested else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    public func delete(_ recipe: RecipeSummary) async {
        do {
            try await repo.delete(id: recipe.id)
            recipes.removeAll { $0.id == recipe.id }
        } catch {
            errorMessage = homeAdminMessage(error)
        }
    }
}
