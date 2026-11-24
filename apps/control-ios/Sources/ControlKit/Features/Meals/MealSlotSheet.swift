import SwiftUI

/// Casilla del menú: receta (filtrada por franja y tiempo), texto libre, sobras o comer fuera, con
/// raciones y comensales. Aplica el cambio en la copia local de `MealsStore`; se guarda desde la semana.
struct MealSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: MealsStore
    let day: String
    let slot: String
    let item: MealPlanItem?
    @State private var recipes: RecipesStore
    @State private var kind: String
    @State private var title: String
    @State private var recipeId: Int64?
    @State private var servings: Int
    @State private var members: Set<Int64>
    @State private var maxMinutes: Int?
    @State private var query = ""

    init(store: MealsStore, recipes: RecipeRepository, day: String, slot: String, item: MealPlanItem?) {
        self.store = store
        self.day = day
        self.slot = slot
        self.item = item
        let recipesStore = RecipesStore(repo: recipes, activeHomeId: { nil })
        recipesStore.slot = slot
        _recipes = State(initialValue: recipesStore)
        _kind = State(initialValue: item?.kind ?? "recipe")
        _title = State(initialValue: item?.title ?? "")
        _recipeId = State(initialValue: item?.recipeId)
        _servings = State(initialValue: item?.servings ?? 2)
        let eaters = (store.profile?.members ?? []).map { Int64($0.homeMemberId) }
        let defaults = eaters.filter { !store.isOut(memberId: Int($0), day: day, slot: slot) }
        _members = State(initialValue: Set(item?.members ?? defaults))
    }

    var body: some View {
        Form {
            Section {
                Picker("Tipo", selection: $kind) {
                    Text("Receta").tag("recipe")
                    Text("Texto").tag("free_text")
                    Text("Sobras").tag("leftovers")
                    Text("Fuera").tag("eat_out")
                }
                .pickerStyle(.segmented)
            }
            switch kind {
            case "recipe": recipeSection
            case "free_text": Section("Qué se come") { TextField("Plato", text: $title) }
            case "leftovers": Section("Sobras de") { TextField("Opcional", text: $title) }
            default: Section("Dónde") { TextField("Opcional", text: $title) }
            }
            if kind != "eat_out" {
                Section("Raciones") { Stepper("\(servings)", value: $servings, in: 1...100) }
            }
            Section("Comensales") {
                ForEach(store.profile?.members ?? []) { member in
                    let id = Int64(member.homeMemberId)
                    let out = store.isOut(memberId: member.homeMemberId, day: day, slot: slot)
                    Toggle(isOn: Binding(get: { members.contains(id) },
                                         set: { if $0 { members.insert(id) } else { members.remove(id) } })) {
                        VStack(alignment: .leading) {
                            Text(member.name)
                            if out { Text("Fuera en esta franja").font(.caption).foregroundStyle(Palette.err) }
                        }
                    }
                }
            }
            if let item { checkSection(item) }
            if item != nil {
                Section {
                    Button("Quitar de la casilla", role: .destructive) {
                        if let item { store.remove(item) }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("\(MealSlotKind.title(slot)) · \(WeekGridView.dayTitle(day, store.timeZone))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { apply() }.disabled(!isValid).accessibilityIdentifier("menu.casilla.listo")
            }
        }
        .task { await recipes.load() }
    }

    /// Ficha de comprobación: avisos de la casilla, «sin avisos (comprobado)» o «sin comprobar» (R1-05).
    @ViewBuilder private func checkSection(_ item: MealPlanItem) -> some View {
        switch store.checkStatus(for: item) {
        case .notApplicable: EmptyView()
        case .clean:
            Section("Comprobación") {
                Label("Sin avisos (comprobado)", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.ok)
            }
        case .unchecked:
            Section("Comprobación") {
                Label("Sin comprobar", systemImage: "questionmark.circle").foregroundStyle(Palette.warn)
                Text("Solo se revisan alergias, intolerancias y dieta de recetas con ingredientes del catálogo. Guarda los cambios y revisa a mano el texto libre, las sobras y los ingredientes escritos a mano.")
                    .font(.caption).foregroundStyle(Palette.inkSoft)
            }
        case .issues:
            Section("Comprobación") {
                ForEach(Array(store.issues(for: item).enumerated()), id: \.offset) { _, issue in
                    Label(WeekGridView.issueDescription(issue, members: store.profile?.members ?? []),
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.err)
                }
            }
        }
    }

    private var recipeSection: some View {
        Section("Receta") {
            TextField("Buscar", text: $query)
                .onSubmit { Task { recipes.query = query; await recipes.load() } }
            Picker("Tiempo", selection: $maxMinutes) {
                Text("Cualquiera").tag(Int?.none)
                Text("Hasta 15 min").tag(Int?.some(15))
                Text("Hasta 30 min").tag(Int?.some(30))
                Text("Hasta 60 min").tag(Int?.some(60))
            }
            .onChange(of: maxMinutes) { _, value in Task { recipes.maxMinutes = value; await recipes.load() } }
            if recipes.recipes.isEmpty {
                Text(recipes.state == .loading ? "Cargando…" : "No hay recetas para esta franja").foregroundStyle(Palette.inkSoft)
            }
            ForEach(recipes.recipes) { recipe in
                Button {
                    recipeId = recipe.id
                    title = recipe.name
                    servings = recipe.servings
                } label: {
                    HStack {
                        Text(recipe.name).foregroundStyle(Palette.ink)
                        Spacer()
                        if let minutes = recipe.minutes { Text("\(minutes) min").font(.caption).foregroundStyle(Palette.inkSoft) }
                        if recipeId == recipe.id { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        kind == "recipe" ? recipeId != nil : (kind == "free_text" ? !title.trimmingCharacters(in: .whitespaces).isEmpty : true)
    }

    private func apply() {
        let updated = MealPlanItem(
            id: item?.id, day: day, slot: slot, position: item?.position ?? 0, kind: kind,
            recipeId: kind == "recipe" ? recipeId : nil,
            title: title.trimmingCharacters(in: .whitespaces),
            servings: kind == "eat_out" ? nil : servings, cookMemberId: item?.cookMemberId,
            members: members.sorted())
        if let item { store.replace(item, with: updated) } else { store.add(updated) }
        dismiss()
    }
}
