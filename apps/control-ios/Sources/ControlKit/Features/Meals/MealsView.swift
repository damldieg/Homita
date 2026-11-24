import SwiftUI

/// Pestaña Menú: Semana · Compra · Recetas. Compra queda vacía hasta la fase 3.
struct MealsView: View {
    enum Section: Hashable { case week, shopping, recipes }

    let services: AppServices
    @State private var store: MealsStore
    @State private var section: Section = .week

    init(services: AppServices) {
        self.services = services
        _store = State(initialValue: MealsStore(
            meals: services.meals, events: services.events, activeHomeId: { services.homeContext.activeHomeId }))
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
                case .shopping: ShoppingPlaceholderView()
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

/// Compra: vacía hasta la fase 3 del planificador.
struct ShoppingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cart").font(.system(size: 36)).foregroundStyle(Palette.inkMuted)
            Text("La lista de la compra llega pronto").font(HomitaFont.inter(17, weight: .semibold)).foregroundStyle(Palette.ink)
            Text("Cuando tengas el menú de la semana, aquí saldrá lo que hay que comprar.")
                .font(HomitaFont.inter(15)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("menu.compra")
    }
}
