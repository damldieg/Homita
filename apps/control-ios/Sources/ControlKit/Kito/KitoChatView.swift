import SwiftUI

/// Hoja del chat de Kito: historial en el móvil, entrada de texto y estado de envío.
struct KitoChatView: View {
    let store: KitoStore
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if store.messages.isEmpty {
                                Text("Hola, soy Kito. Pregúntame por tus eventos, rutinas, tareas o personas del hogar.")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 24)
                            }
                            ForEach(store.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if store.isSending {
                                ProgressView().padding(.leading, 4).id("sending")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: store.messages.count) { _, _ in
                        if let last = store.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                if let error = store.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                HStack(spacing: 8) {
                    TextField("Escribe a Kito", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
                    .accessibilityLabel("Enviar")
                }
                .padding(12)
            }
            .navigationTitle("Kito")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func bubble(_ message: KitoMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await store.send(text) }
    }
}
