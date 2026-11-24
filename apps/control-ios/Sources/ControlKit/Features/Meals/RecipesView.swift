import SwiftUI

/// Pestaña Recetas (lista con búsqueda). La ficha y el editor llegan en T19.
struct RecipesView: View {
    @State private var store: RecipesStore

    init(services: AppServices) {
        _store = State(initialValue: RecipesStore(
            repo: services.recipes, activeHomeId: { services.homeContext.activeHomeId }))
    }

    var body: some View {
        List(store.recipes) { recipe in
            Text(recipe.name)
        }
        .overlay { if store.recipes.isEmpty { Text("Aún no hay recetas").foregroundStyle(Palette.inkSoft) } }
        .task { await store.load() }
    }
}
