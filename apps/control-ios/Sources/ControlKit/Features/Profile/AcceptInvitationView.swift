import SwiftUI

/// Unirse a un hogar con un código de invitación (1.15, D-016). Vive en Perfil, fuera de
/// `HomeGate`: es alcanzable sin hogar activo (`.noHome`, `.failed`) y con uno (`.ready`).
/// El código lo da un administrador del hogar (se copia, sin email: D14); solo sirve una vez y
/// caduca a los 7 días. Tras unirse, el hogar pasa a ser el activo (`HomeContextStore`).
struct AcceptInvitationView: View {
    let services: AppServices

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var joinedHomeName: String?

    var body: some View {
        HomitaForm {
            HomitaPanel("Código de invitación", systemImage: "ticket") {
                HomitaField(placeholder: "32 caracteres", text: $code, isCode: true)
                HomitaFootnote(text: "Pídeselo a un administrador del hogar. Solo sirve una vez y caduca a los 7 días.")
            }
            HomitaPrimaryButton(title: "Unirse", isEnabled: InvitationCode.isValid(code) && !isWorking, isLoading: isWorking) {
                Task { await accept() }
            }
            if let joinedHomeName {
                HomitaPanel("Listo", systemImage: "checkmark.circle", tint: Palette.online) {
                    Text("Te has unido a \(joinedHomeName)")
                        .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
        .navigationTitle("Unirse a un hogar")
        .errorAlert($errorMessage)
        .overlay {
            if isWorking {
                HomitaLoadingOverlay(message: "Uniéndote…")
            }
        }
        .disabled(isWorking)
    }

    private func accept() async {
        isWorking = true
        defer { isWorking = false }
        joinedHomeName = nil
        if let message = await services.homeContext.acceptInvitation(code: code, using: services.homes) {
            errorMessage = message
            return
        }
        code = ""
        switch services.homeContext.state {
        case .ready(let home):
            joinedHomeName = home.name
        case .failed(let message):
            // La membresía ya existe; la recarga del hogar falló (Reintentar en Tareas/Calendario).
            errorMessage = message
        default:
            break
        }
    }
}
