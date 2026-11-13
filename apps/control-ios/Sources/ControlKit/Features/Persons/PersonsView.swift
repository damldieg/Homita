import SwiftUI

/// Personas: CRUD de las propias; las compartidas (`editable=false`, de co-miembros de
/// calendario) son solo lectura y no muestran acciones (`PersonActions`).
struct PersonsView: View {
    @Bindable var store: PersonStore

    @State private var showCreate = false
    @State private var personToEdit: PersonEntry?
    @State private var pendingPersonDelete: PersonEntry?
    @State private var showPersonDelete = false

    /// Fila de la lista (AJ-03): punto de color, nombre, badge si es compartida y lápiz/papelera solo en las propias.
    private func personRow(_ person: PersonEntry) -> some View {
        let actions = PersonActions.available(editable: person.isEditable)
        return HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: person.color))
                .frame(width: 14, height: 14)
            Text(person.name)
                .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if !person.isEditable {
                HomitaBadge(title: "Compartida (solo lectura)", tintHex: Palette.inkSoftHex)
            }
            Spacer(minLength: 8)
            if actions.contains(.edit) {
                Button {
                    personToEdit = person
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Editar \(person.name)")
                .accessibilityIdentifier("personas.editar.\(person.id)")
            }
            if actions.contains(.delete) {
                Button {
                    pendingPersonDelete = person
                    showPersonDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.err)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .homitaRequiresNetwork()
                .accessibilityLabel("Eliminar \(person.name)")
                .accessibilityIdentifier("personas.eliminar.\(person.id)")
            }
        }
    }

    var body: some View {
        List {
            // AJ-03 estado 3: esqueleto mientras carga (sin texto de «Cargando»).
            if store.isLoading && store.persons.isEmpty {
                HomitaSkeletonRows(count: 3, height: 52, label: "Cargando personas").homitaRow()
            }
            if !store.persons.isEmpty {
                Section {
                    ForEach(store.persons, id: \.id) { person in
                        personRow(person)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.visible, edges: .bottom)
                            .listRowSeparatorTint(Palette.line)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                } header: {
                    HomitaSectionHeader(title: "Personas", count: store.persons.count, systemImage: "person.2")
                }
                if store.persons.contains(where: { !$0.isEditable }) {
                    Text("Las personas compartidas vienen de otro hogar. Su nombre y color se cambian desde ese hogar.")
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            if let failure = store.loadFailure, store.persons.isEmpty, !store.isLoading {
                HomeErrorView(message: failure, title: "No se pudieron cargar las personas") { Task { await store.load() } }
                    .homitaRow()
            } else if store.persons.isEmpty && !store.isLoading {
                HomitaCard {
                    HomitaEmptyNote(text: HomitaEmptyNoteText.persons)
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
        .writeFailureToast($store.writeFailure)
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
    @State private var showDeleteConfirm = false

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
                        HomitaColorField(title: "Color", color: $color)
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
                .homitaRequiresNetwork()
                .accessibilityIdentifier("persona-editor.guardar")
                if let editing {
                    HomitaButton(title: "Eliminar persona", kind: .secondary) { showDeleteConfirm = true }
                        .homitaRequiresNetwork()
                        .accessibilityIdentifier("persona-editor.eliminar")
                        .homitaConfirm(
                            DeleteConfirmation.message(names: [editing.name], consequence: "Se eliminará la persona."),
                            isPresented: $showDeleteConfirm, confirmTitle: "Eliminar"
                        ) {
                            Task { if await store.delete(editing) { dismiss() } }
                        }
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
        // «Reintentar» que va bien cierra el editor, igual que un guardado correcto.
        .writeFailureToast($store.writeFailure) { dismiss() }
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
