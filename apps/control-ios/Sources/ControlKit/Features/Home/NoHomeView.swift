import SwiftUI

/// Estado sin hogar: permite crear el primero (`POST home/create`).
struct NoHomeView: View {
    let services: AppServices
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HomitaForm {
            HomitaHeader(title: "Hogar")
            if let code = services.homeContext.pendingInvitationCode {
                pendingInvitationPanel(code)
            }
            HomitaPanel("No tienes ningún hogar", systemImage: "house") {
                HomitaFootnote(text: "Crea uno para empezar a usar tareas y calendarios.")
                HomitaField(placeholder: "Nombre del hogar", text: $name)
            }
            HomitaPrimaryButton(title: "Crear hogar", isEnabled: !trimmed.isEmpty && !isWorking, isLoading: isWorking) {
                Task {
                    isWorking = true
                    errorMessage = await services.homeContext.create(name: trimmed, using: services.homes)
                    isWorking = false
                }
            }
            .homitaRequiresNetwork()
            .accessibilityIdentifier("sin-hogar.crear-hogar")
        }
        .errorAlert($errorMessage)
    }

    /// Invitación con la que se acaba de registrar (0023): en espera hasta que la acepta aquí.
    private func pendingInvitationPanel(_ code: String) -> some View {
        HomitaPanel("Tienes una invitación", systemImage: "envelope.badge") {
            HomitaFootnote(text: "Aceptarla te une al hogar. Hasta que la aceptes, la invitación queda en espera.")
            HomitaPrimaryButton(title: "Aceptar invitación", isEnabled: !isWorking, isLoading: isWorking) {
                Task { await acceptPending(code) }
            }
            .homitaRequiresNetwork()
            .accessibilityIdentifier("sin-hogar.aceptar-invitacion")
            HomitaButton(title: "Ahora no", kind: .secondary) {
                services.homeContext.pendingInvitationCode = nil
            }
        }
    }

    private func acceptPending(_ code: String) async {
        isWorking = true
        defer { isWorking = false }
        if let message = await services.homeContext.acceptInvitation(code: code, using: services.homes) {
            errorMessage = message
            return
        }
        services.homeContext.pendingInvitationCode = nil
    }
}
