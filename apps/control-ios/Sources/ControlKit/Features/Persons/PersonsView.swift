import SwiftUI

/// Personas: CRUD de las propias; las compartidas (`editable=false`, de co-miembros de
/// calendario) son solo lectura y no muestran acciones (`PersonActions`).
struct PersonsView: View {
    @Bindable var store: PersonStore

    @State private var showCreate = false
    @State private var personToEdit: PersonEntry?

    var body: some View {
        List {
            Section {
                ForEach(store.persons, id: \.id) { person in
                    HomitaCard {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: person.color))
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                                    .foregroundStyle(Palette.ink)
                                if !person.isEditable {
                                    HomitaBadge(title: "Compartida (solo lectura)", tintHex: Palette.inkSoftHex)
                                }
                            }
                            Spacer()
                            if PersonActions.available(editable: person.isEditable).contains(.edit) {
                                Button {
                                    personToEdit = person
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(Palette.ink)
                                }
                                .buttonStyle(.borderless)
                            }
                            if PersonActions.available(editable: person.isEditable).contains(.delete) {
                                Button(role: .destructive) {
                                    Task { await store.delete(person) }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .homitaRow()
                }
            } header: {
                HomitaSectionHeader(title: "Personas", count: store.persons.count, systemImage: "person.2")
            }
            if store.persons.isEmpty && !store.isLoading {
                HomitaCard {
                    Text("Sin personas")
                        .font(HomitaFont.inter(16, relativeTo: .body))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                }
                .homitaRow()
            }
        }
        .homitaList()
        .navigationTitle("Personas")
        .homitaNavigationBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Nueva persona")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                PersonEditorView(store: store, editing: nil)
            }
        }
        .sheet(item: $personToEdit) { person in
            NavigationStack {
                PersonEditorView(store: store, editing: person)
            }
        }
        .refreshable {
            await store.load()
        }
        .errorAlert($store.errorMessage)
    }
}

/// Editor de persona: nombre y color `#RRGGBB`.
struct PersonEditorView: View {
    @Bindable var store: PersonStore
    let editing: PersonEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: Color
    @State private var isWorking = false

    init(store: PersonStore, editing: PersonEntry?) {
        self.store = store
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: Color(hex: editing?.color ?? Palette.fallbackItem))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomitaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HomitaSectionHeader(title: "Persona", systemImage: "person.crop.circle")
                        HomitaField(placeholder: "Nombre (1-50)", text: $name)
                        ColorPicker("Color", selection: $color, supportsOpacity: false)
                            .font(HomitaFont.inter(17, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                    }
                }
                HomitaPrimaryButton(
                    title: editing == nil ? "Crear persona" : "Guardar",
                    isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking,
                    isLoading: isWorking
                ) {
                    Task { await save() }
                }
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(editing == nil ? "Nueva persona" : "Editar persona")
        .homitaNavigationBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
        .errorAlert($store.errorMessage)
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (1...50).contains(trimmed.codepointCount), color.hexString.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil else {
            store.errorMessage = "El nombre debe tener 1-50 caracteres y el color formato #RRGGBB"
            return
        }
        let ok = await store.save(name: trimmed, color: color.hexString, editing: editing)
        if ok { dismiss() }
    }
}
