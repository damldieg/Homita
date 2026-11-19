import SwiftUI

/// Formulario de feedback (bug o mejora) desde Ajustes: sección, sub-área y acción dependientes,
/// tipo (radio, sin valor por defecto) y texto libre. Sin conexión el envío queda bloqueado.
struct FeedbackView: View {
    @State private var store: FeedbackStore
    @State private var showThanks = false
    @Environment(\.dismiss) private var dismiss

    init(repo: FeedbackRepository) {
        _store = State(initialValue: FeedbackStore(repo: repo))
    }

    /// El radio trabaja con opcionales: se enlaza al tipo del borrador sin valor inicial.
    private var kindBinding: Binding<FeedbackKind?> {
        Binding(get: { store.draft.kind }, set: { store.selectKind($0) })
    }

    var body: some View {
        HomitaForm {
            HomitaPanel("¿Dónde?", systemImage: "square.grid.2x2") {
                selectorRow(title: "Sección", value: store.draft.section?.name, identifier: "feedback.seccion") {
                    ForEach(store.sections, id: \.self) { section in
                        Button(section.name) { store.selectSection(section) }
                    }
                }
                if store.draft.section != nil {
                    selectorRow(title: "Sub-área", value: store.draft.areaName, identifier: "feedback.subarea") {
                        ForEach(store.areas, id: \.self) { area in
                            Button(area.name.capitalizedFirst) { store.selectArea(area) }
                        }
                    }
                }
                if store.draft.area != nil {
                    selectorRow(title: "Acción", value: store.draft.action?.title, identifier: "feedback.accion") {
                        ForEach(store.actions, id: \.self) { action in
                            Button(action.title) { store.selectAction(action) }
                        }
                    }
                }
            }
            HomitaPanel("Tipo", systemImage: "tag") {
                HomitaRadioGroup(selection: kindBinding, items: FeedbackKind.allCases.map { (id: $0, title: $0.title) })
                    .accessibilityIdentifier("feedback.tipo")
            }
            HomitaPanel("Cuéntanos", systemImage: "text.bubble") {
                HomitaTextEditor(placeholder: "Qué pasó o qué mejorarías", text: $store.text)
                    .accessibilityIdentifier("feedback.texto")
            }
            if let message = store.errorMessage {
                HomitaErrorText(text: message)
            }
            HomitaPrimaryButton(
                title: "Enviar feedback",
                isEnabled: store.canSubmit(isOffline: DataFreshness.shared.isOffline),
                isLoading: store.isWorking
            ) {
                Task {
                    if await store.submit(isOffline: DataFreshness.shared.isOffline) { showThanks = true }
                }
            }
            .homitaRequiresNetwork(reason: "No se puede enviar sin conexión.")
            .accessibilityIdentifier("feedback.enviar")
        }
        .navigationTitle("Enviar feedback")
        .disabled(store.isWorking)
        .overlay {
            if store.isWorking {
                HomitaLoadingOverlay(message: "Enviando…")
            }
        }
        .alert("¡Gracias! Hemos recibido tu feedback.", isPresented: $showThanks) {
            Button("Cerrar") { dismiss() }
        }
    }

    private func selectorRow<Items: View>(
        title: String, value: String?, identifier: String, @ViewBuilder items: @escaping () -> Items
    ) -> some View {
        HomitaLabeledRow(title) {
            Menu {
                items()
            } label: {
                HStack(spacing: 4) {
                    Text(value?.capitalizedFirst ?? "Elegir")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(HomitaFont.inter(15, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(value == nil ? Palette.accent : Palette.ink)
            }
            .accessibilityIdentifier(identifier)
        }
    }
}

private extension String {
    /// Primera letra en mayúscula (las sub-áreas del catálogo van en minúscula).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
