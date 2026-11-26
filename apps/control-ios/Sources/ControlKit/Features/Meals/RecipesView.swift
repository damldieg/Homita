import SwiftUI

/// Pestaña Recetas: lista con búsqueda y filtro por franja; la ficha y el editor se abren desde aquí.
struct RecipesView: View {
    let services: AppServices
    @State private var store: RecipesStore
    @State private var editing: RecipeEditorRequest?

    init(services: AppServices) {
        self.services = services
        _store = State(initialValue: RecipesStore(
            repo: services.recipes, activeHomeId: { services.homeContext.activeHomeId }))
    }

    var body: some View {
        List {
            Section {
                TextField("Buscar receta", text: $store.query)
                    .submitLabel(.search)
                    .onSubmit { Task { await store.load() } }
                Picker("Franja", selection: $store.slot) {
                    Text("Todas").tag(String?.none)
                    ForEach(MealSlotKind.order, id: \.self) { Text(MealSlotKind.title($0)).tag(String?.some($0)) }
                }
                .onChange(of: store.slot) { _, _ in Task { await store.load() } }
                if !store.countries.isEmpty {
                    Picker("País de las recetas comunes", selection: $store.country) {
                        Text("Todos").tag(String?.none)
                        ForEach(store.countries, id: \.self) { Text(RecipeCountry.name($0)).tag(String?.some($0)) }
                    }
                    .accessibilityIdentifier("recetas.pais")
                }
            }
            if case .failed(let message) = store.state {
                Text(message).foregroundStyle(Palette.inkSoft)
            } else if store.recipes.isEmpty, store.state == .loaded {
                Text("Aún no hay recetas. Crea la primera con «Nueva».").foregroundStyle(Palette.inkSoft)
            }
            ForEach(store.recipes) { recipe in
                NavigationLink(value: recipe.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name).font(HomitaFont.inter(16, weight: .medium)).foregroundStyle(Palette.ink)
                        Text(Self.subtitle(recipe)).font(HomitaFont.inter(13)).foregroundStyle(Palette.inkSoft)
                    }
                }
                .swipeActions {
                    if !recipe.isCommon {
                        Button("Borrar", role: .destructive) { Task { await store.delete(recipe) } }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva", systemImage: "plus") { editing = RecipeEditorRequest(recipe: nil) }
                    .accessibilityIdentifier("recetas.nueva")
            }
        }
        .navigationDestination(for: Int64.self) { id in
            RecipeDetailView(services: services, recipeId: id) { Task { await store.load() } }
        }
        .sheet(item: $editing) { request in
            NavigationStack {
                RecipeEditorView(services: services, recipe: request.recipe) { _ in
                    editing = nil
                    Task { await store.load() }
                }
            }
        }
        .errorAlert($store.errorMessage)
        .task { await store.load() }
    }

    static func subtitle(_ recipe: RecipeSummary) -> String {
        var parts = ["\(recipe.servings) raciones"]
        if let minutes = recipe.minutes { parts.append("\(minutes) min") }
        if !recipe.slots.isEmpty { parts.append(recipe.slots.map(MealSlotKind.title).joined(separator: ", ")) }
        if recipe.isCommon, let country = recipe.country { parts.append(RecipeCountry.name(country)) }
        return parts.joined(separator: " · ")
    }
}

struct RecipeEditorRequest: Identifiable {
    let recipe: Recipe?
    var id: Int64 { recipe?.id ?? 0 }
}

/// Ficha de una receta (solo lectura, con «Editar»). La abren la lista y la tarjeta de Inicio.
struct RecipeDetailView: View {
    let services: AppServices
    let recipeId: Int64
    var onChanged: () -> Void = {}
    @State private var recipe: Recipe?
    @State private var message: String?
    @State private var editing: RecipeEditorRequest?

    var body: some View {
        Group {
            if let recipe {
                List {
                    Section {
                        Text(RecipesView.subtitle(RecipeSummary(
                            id: recipe.id, name: recipe.name, servings: recipe.servings, minutes: recipe.minutes, slots: recipe.slots,
                            homeId: recipe.homeId, country: recipe.country)))
                            .foregroundStyle(Palette.inkSoft)
                        if !recipe.allergens.isEmpty {
                            Label("Alérgenos: " + recipe.allergens.map(Self.allergenName).joined(separator: ", "),
                                  systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warn)
                        }
                    }
                    Section("Ingredientes") {
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ing in
                            HStack {
                                Text(ing.label ?? "")
                                Spacer()
                                Text(Self.amount(ing)).foregroundStyle(Palette.inkSoft)
                            }
                        }
                    }
                    if let steps = recipe.steps, !steps.isEmpty {
                        Section("Pasos") {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in Text("\(index + 1). \(step)") }
                        }
                    }
                }
            } else if let message {
                Text(message).foregroundStyle(Palette.inkSoft).padding(24)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe?.name ?? "Receta")
        .toolbar {
            if let recipe, !recipe.isCommon {
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { editing = RecipeEditorRequest(recipe: recipe) }
                }
            }
        }
        .sheet(item: $editing) { request in
            NavigationStack {
                RecipeEditorView(services: services, recipe: request.recipe) { saved in
                    recipe = saved
                    editing = nil
                    onChanged()
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { recipe = try await services.recipes.detail(id: recipeId) } catch { message = homeAdminMessage(error) }
    }

    static func amount(_ ing: RecipeIngredient) -> String {
        let unit = ing.unit ?? ""
        guard let quantity = ing.quantity else { return unit == "al gusto" ? unit : "" }
        let number = quantity == quantity.rounded() ? String(Int(quantity)) : String(quantity)
        return "\(number) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    static func allergenName(_ key: String) -> String {
        MealRules.allergens.first { $0.0 == key }?.1 ?? key
    }
}

/// Alta o edición de receta: datos, ingredientes (autocompletar del catálogo o texto libre) y pasos.
struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let services: AppServices
    let onSaved: (Recipe) -> Void
    @State private var draft: RecipeDraft
    @State private var foodQuery = ""
    @State private var suggestions: [Food] = []
    @State private var newStep = ""
    @State private var saving = false
    @State private var message: String?

    init(services: AppServices, recipe: Recipe?, onSaved: @escaping (Recipe) -> Void) {
        self.services = services
        self.onSaved = onSaved
        _draft = State(initialValue: recipe.map(RecipeDraft.init) ?? RecipeDraft())
    }

    var body: some View {
        Form {
            Section("Receta") {
                TextField("Nombre", text: $draft.name)
                Stepper("Raciones: \(draft.servings)", value: $draft.servings, in: 1...100)
                Stepper(draft.minutes.map { "Tiempo: \($0) min" } ?? "Tiempo: sin indicar",
                        value: Binding(get: { draft.minutes ?? 0 }, set: { draft.minutes = $0 }), in: 0...1440, step: 5)
                if draft.minutes != nil { Button("Quitar tiempo") { draft.minutes = nil } }
            }
            Section("Franjas sugeridas") {
                ForEach(MealSlotKind.order, id: \.self) { slot in
                    Toggle(MealSlotKind.title(slot), isOn: Binding(
                        get: { draft.slots.contains(slot) },
                        set: { on in
                            draft.slots.removeAll { $0 == slot }
                            if on { draft.slots.append(slot) }
                        }))
                }
            }
            Section("Ingredientes") {
                ForEach(Array(draft.ingredients.enumerated()), id: \.offset) { index, _ in ingredientRow(index) }
                    .onDelete { offsets in offsets.sorted(by: >).forEach { draft.removeIngredient(at: $0) } }
                TextField("Añadir ingrediente (busca en el catálogo)", text: $foodQuery)
                    .accessibilityIdentifier("receta.ingrediente")
                ForEach(suggestions) { food in
                    Button { draft.addIngredient(food); foodQuery = ""; suggestions = [] } label: {
                        HStack {
                            Text(food.name).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(food.homeId == nil ? "Catálogo" : "Mío").font(.caption).foregroundStyle(Palette.inkSoft)
                        }
                    }
                }
                if !foodQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Usar «\(foodQuery)» como texto libre") {
                        draft.addFreeIngredient(foodQuery)
                        foodQuery = ""
                        suggestions = []
                    }
                }
            }
            Section("Pasos (opcional)") {
                ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in Text("\(index + 1). \(step)") }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                HStack {
                    TextField("Nuevo paso", text: $newStep)
                    Button("Añadir") {
                        draft.steps.append(newStep)
                        newStep = ""
                    }
                    .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(draft.id == nil ? "Nueva receta" : "Editar receta")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { Task { await save() } }
                    .disabled(!draft.isValid || saving)
                    .accessibilityIdentifier("receta.guardar")
            }
        }
        .errorAlert($message)
        .task(id: foodQuery) {
            let query = foodQuery.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            suggestions = (try? await services.recipes.searchFood(query, limit: 8)) ?? []
        }
    }

    private func ingredientRow(_ index: Int) -> some View {
        let ing = draft.ingredients[index]
        return HStack {
            Text(ing.label ?? "").lineLimit(1)
            Spacer()
            TextField("Cant.", text: Binding(
                get: { ing.quantity.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "" },
                set: { draft.ingredients[index].quantity = Double($0.replacingOccurrences(of: ",", with: ".")) }))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Picker("Unidad", selection: Binding(
                get: { ing.unit ?? "ud" }, set: { draft.ingredients[index].unit = $0 })) {
                ForEach(RecipeUnit.all, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let saved: Recipe
            if let id = draft.id {
                saved = try await services.recipes.update(id: id, draft.input())
            } else {
                saved = try await services.recipes.create(draft.input())
            }
            onSaved(saved)
        } catch {
            message = homeAdminMessage(error)
        }
    }
}
