import Foundation

/// Lista de recetas del hogar y las comunes precargadas, con búsqueda y filtros (franja, tiempo máximo y
/// país de las comunes). La usan la pestaña Recetas y el selector de receta de la casilla (que no admite
/// las comunes: solo se planifican recetas del hogar, `includeCommon = false`).
@Observable
public final class RecipesStore {
    /// Lo que devuelve el servidor, sin el filtro de país.
    public private(set) var allRecipes: [RecipeSummary] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?
    public var query = ""
    public var slot: String?
    public var maxMinutes: Int?
    /// Código ISO del filtro de país; solo recorta las recetas comunes (las del hogar siempre se ven).
    public var country: String?
    public var includeCommon = true

    private let repo: RecipeRepository
    private let activeHomeId: () -> String?

    public init(repo: RecipeRepository, activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.activeHomeId = activeHomeId
    }

    /// Recetas visibles: sin las comunes si `includeCommon` es falso; con país elegido, solo las comunes de ese país.
    public var recipes: [RecipeSummary] {
        allRecipes.filter { recipe in
            guard recipe.isCommon else { return true }
            return includeCommon && (country == nil || recipe.country == country)
        }
    }

    /// Países de las recetas comunes presentes en la lista, ordenados por nombre.
    public var countries: [String] {
        guard includeCommon else { return [] }
        return Array(Set(allRecipes.compactMap { $0.isCommon ? $0.country : nil }))
            .sorted { RecipeCountry.name($0).localizedCompare(RecipeCountry.name($1)) == .orderedAscending }
    }

    public func load() async {
        let requested = activeHomeId()
        state = .loading
        do {
            let list = try await repo.list(query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                           slot: slot, maxMinutes: maxMinutes)
            guard activeHomeId() == requested else { return }
            allRecipes = list
            if let country, !countries.contains(country) { self.country = nil }
            state = .loaded
        } catch {
            guard activeHomeId() == requested else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    public func delete(_ recipe: RecipeSummary) async {
        do {
            try await repo.delete(id: recipe.id)
            allRecipes.removeAll { $0.id == recipe.id }
        } catch {
            errorMessage = homeAdminMessage(error)
        }
    }
}
