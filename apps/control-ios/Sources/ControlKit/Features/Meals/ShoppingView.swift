import SwiftUI

/// Menú › Compra: la lista del hogar por sección. Tocar una fila marca o desmarca; deslizar da «Ya lo
/// tengo», cantidad y borrar. Los de origen menú muestran «para qué plato es».
struct ShoppingView: View {
    @Bindable var store: ShoppingStore
    @State private var newLabel = ""
    @State private var newQuantity = ""
    @State private var newUnit = "ud"
    @State private var pickedFood: Food?
    @State private var quantityEditing: ShoppingItem?
    @State private var quantityText = ""

    var body: some View {
        List {
            if let notice = store.changeNotice {
                HStack {
                    Label(notice, systemImage: "arrow.triangle.2.circlepath")
                        .font(HomitaFont.inter(14)).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Entendido") { store.dismissChanges() }
                        .font(HomitaFont.inter(14, weight: .semibold))
                        .accessibilityIdentifier("compra.aviso.cerrar")
                }
                .accessibilityIdentifier("compra.aviso")
            }
            addSection
            if case .failed(let message) = store.state {
                Text(message).foregroundStyle(Palette.inkSoft)
            } else if store.isEmpty, store.state == .loaded {
                Text("La compra está vacía. Acepta el menú de la semana o añade algo a mano.")
                    .font(HomitaFont.inter(15)).foregroundStyle(Palette.inkSoft)
            }
            ForEach(store.sections, id: \.section) { group in
                Section(ShoppingFormat.sectionTitle(group.section)) {
                    ForEach(group.items) { item in row(item) }
                }
            }
            if store.checkedCount > 0 {
                Button("Vaciar comprados (\(store.checkedCount))", role: .destructive) { Task { await store.clearChecked() } }
                    .accessibilityIdentifier("compra.vaciar")
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("menu.compra")
        .errorAlert($store.errorMessage)
        .refreshable { await store.load() }
        .task { await store.load() }
        .alert("Cantidad", isPresented: Binding(get: { quantityEditing != nil }, set: { if !$0 { quantityEditing = nil } })) {
            TextField("Cantidad", text: $quantityText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Guardar") {
                if let item = quantityEditing, let value = Self.parse(quantityText) {
                    Task { await store.updateQuantity(item, quantity: value) }
                }
                quantityEditing = nil
            }
            Button("Cancelar", role: .cancel) { quantityEditing = nil }
        } message: {
            Text(quantityEditing.map { "\($0.label) (\($0.unit))" } ?? "")
        }
    }

    // MARK: Alta a mano

    @ViewBuilder private var addSection: some View {
        Section {
            HStack {
                TextField("Añadir a la compra", text: $newLabel)
                    .submitLabel(.done)
                    .onSubmit { Task { await add() } }
                    .accessibilityIdentifier("compra.nuevo")
                TextField("Cant.", text: $newQuantity)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Picker("Unidad", selection: $newUnit) {
                    ForEach(ShoppingView.units, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Añadir", systemImage: "plus.circle.fill") { Task { await add() } }
                    .labelStyle(.iconOnly)
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty && pickedFood == nil)
                    .accessibilityIdentifier("compra.anadir")
            }
            ForEach(store.suggestions) { food in
                Button {
                    pickedFood = food
                    newLabel = food.name
                    newUnit = ShoppingView.units.contains(food.defaultUnit) ? food.defaultUnit : "ud"
                } label: {
                    Text(food.name).foregroundStyle(Palette.ink)
                }
            }
        }
        .task(id: newLabel) {
            if pickedFood?.name == newLabel { return }
            pickedFood = nil
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await store.suggest(newLabel)
        }
    }

    static let units = ["g", "kg", "ml", "l", "ud", "cda", "cdta", "pizca"]

    private func add() async {
        let ok = await store.add(label: newLabel, quantity: Self.parse(newQuantity), unit: newUnit, food: pickedFood)
        if ok {
            newLabel = ""
            newQuantity = ""
            pickedFood = nil
        }
    }

    // MARK: Filas

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            Task { await store.toggle(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : (item.isSkipped ? "house.circle.fill" : "circle"))
                    .foregroundStyle(item.isPending ? Palette.inkMuted : Palette.accent)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(HomitaFont.inter(16, weight: .medium))
                        .foregroundStyle(item.isPending ? Palette.ink : Palette.inkMuted)
                        .strikethrough(item.isChecked)
                    if let detail = Self.detail(item) {
                        Text(detail).font(HomitaFont.inter(13)).foregroundStyle(Palette.inkSoft)
                    }
                }
                Spacer()
                Text(item.quantityText).font(HomitaFont.inter(15)).foregroundStyle(Palette.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("compra.fila.\(item.id)")
        .swipeActions(edge: .leading) {
            Button(item.isSkipped ? "Pendiente" : "Ya lo tengo") { Task { await store.haveIt(item) } }
                .tint(Palette.accent)
        }
        .swipeActions(edge: .trailing) {
            Button("Borrar", role: .destructive) { Task { await store.delete(item) } }
            Button("Cantidad") {
                quantityText = item.quantity.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
                quantityEditing = item
            }
        }
    }

    /// «Para: Lasaña, Ensalada» (platos distintos) y «Ya lo tengo» si aplica.
    static func detail(_ item: ShoppingItem) -> String? {
        var parts: [String] = []
        if item.isSkipped { parts.append("Ya lo tengo") }
        var seen = Set<String>()
        let dishes = item.sources.compactMap(\.name).filter { seen.insert($0).inserted }
        if !dishes.isEmpty { parts.append("Para: " + dishes.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
