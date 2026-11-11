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
        Form {
            Section {
                codeField
            } header: {
                Text("Código de invitación")
            } footer: {
                Text("Pídeselo a un administrador del hogar. Solo sirve una vez y caduca a los 7 días.")
            }
            Section {
                Button {
                    Task { await accept() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Unirse")
                    }
                }
                .disabled(!InvitationCode.isValid(code) || isWorking)
            }
            if let joinedHomeName {
                Section {
                    Label("Te has unido a \(joinedHomeName)", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("Unirse a un hogar")
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private var codeField: some View {
        #if os(iOS)
        TextField("32 caracteres", text: $code)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
        #else
        TextField("32 caracteres", text: $code)
            .font(.body.monospaced())
        #endif
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
