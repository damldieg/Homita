import SwiftUI

/// Personas: CRUD de las propias; las compartidas (`editable=false`, de co-miembros de
/// calendario) son solo lectura y no muestran acciones (`PersonActions`).
struct PersonsView: View {
    @Bindable var store: PersonStore

    @State private var showCreate = false
    @State private var personToEdit: PersonEntry?

    var body: some View {
        List {
            ForEach(store.persons, id: \.id) { person in
                HStack {
                    Circle()
                        .fill(Color(hex: person.color))
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(person.name)
                        if !person.isEditable {
                            Text("Compartida (solo lectura)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if PersonActions.available(editable: person.isEditable).contains(.edit) {
                        Button {
                            personToEdit = person
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                    }
                    if PersonActions.available(editable: person.isEditable).contains(.delete) {
                        Button(role: .destructive) {
                            Task { await store.delete(person) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if store.persons.isEmpty && !store.isLoading {
                Text("Sin personas")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Personas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Label("Nueva persona", systemImage: "plus")
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
        _color = State(initialValue: Color(hex: editing?.color ?? "#6923E2"))
    }

    var body: some View {
        Form {
            Section("Persona") {
                TextField("Nombre (1-50)", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
            Section {
                Button(editing == nil ? "Crear persona" : "Guardar") {
                    Task { await save() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
        }
        .navigationTitle(editing == nil ? "Nueva persona" : "Editar persona")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
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
