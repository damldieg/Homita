import SwiftUI

/// Pestaña Menú: Semana · Compra · Recetas.
struct MealsView: View {
    enum Section: Hashable { case week, shopping, recipes }

    let services: AppServices
    @State private var store: MealsStore
    @State private var shopping: ShoppingStore
    @State private var section: Section = .week

    init(services: AppServices) {
        self.services = services
        _store = State(initialValue: MealsStore(
            meals: services.meals, events: services.events, activeHomeId: { services.homeContext.activeHomeId }))
        _shopping = State(initialValue: ShoppingStore(
            repo: services.shopping, searchFoods: { try await services.recipes.searchFood($0, limit: 8) },
            activeHomeId: { services.homeContext.activeHomeId }))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HomitaSegmented(selection: $section, items: [
                    (id: .week, title: "Semana"), (id: .shopping, title: "Compra"), (id: .recipes, title: "Recetas"),
                ])
                .padding(.horizontal, 16)
                .padding(.top, 8)
                switch section {
                case .week: WeekGridView(store: store, services: services)
                case .shopping: ShoppingView(store: shopping)
                case .recipes: RecipesView(services: services)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Menú")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
