import SwiftUI

/// Personas: CRUD de las propias; las compartidas (`editable=false`, de co-miembros de
/// calendario) son solo lectura y no muestran acciones (`PersonActions`).
struct PersonsView: View {
    @Bindable var store: PersonStore

    @State private var showCreate = false
    @State private var personToEdit: PersonEntry?
    @State private var pendingPersonDelete: PersonEntry?
    @State private var showPersonDelete = false

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
                                .accessibilityLabel("Editar \(person.name)")
                                .accessibilityIdentifier("personas.editar.\(person.id)")
                            }
                            if PersonActions.available(editable: person.isEditable).contains(.delete) {
                                Button(role: .destructive) {
                                    pendingPersonDelete = person
                                    showPersonDelete = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Eliminar \(person.name)")
                                .accessibilityIdentifier("personas.eliminar.\(person.id)")
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
                    HomitaEmptyNote(text: "Sin personas")
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
                        .accessibilityIdentifier("personas.alta")
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
        .homitaConfirm(DeleteConfirmation.message(names: pendingPersonDelete.map { [$0.name] } ?? [], consequence: "Se eliminará la persona."), isPresented: $showPersonDelete, confirmTitle: "Eliminar") {
            if let person = pendingPersonDelete { Task { await store.delete(person) } }
        }
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
    /// El error del nombre aparece solo después de que el usuario toque el campo.
    @State private var nameTouched = false

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
                        HomitaFormField(
                            placeholder: "Nombre (1-50)",
                            text: $name,
                            error: nameTouched ? MemberValidation.nameMessage(name) : nil
                        )
                        .onChange(of: name) { _, _ in nameTouched = true }
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
