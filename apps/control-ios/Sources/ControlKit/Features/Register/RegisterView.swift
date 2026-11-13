import SwiftUI

/// Registro (`POST user/create`), solo visible si `GET /config` → `allow_registration=true`
/// (producción lo tiene desactivado). Validación de cliente igual que el contrato PHP.
public struct RegisterView: View {
    let services: AppServices

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var invitationCode = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    /// Cuenta creada sin sesión: lleva al login con los datos cargados.
    @State private var showLogin = false

    public init(services: AppServices) {
        self.services = services
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomitaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HomitaSectionHeader(title: "Cuenta", systemImage: "person.badge.plus")
                        HomitaField(placeholder: "Nombre", text: $name)
                        HomitaField(placeholder: "Email", text: $email, isEmail: true)
                        HomitaField(placeholder: "Contraseña (mínimo 8)", text: $password, isSecure: true)
                    }
                }
                HomitaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HomitaSectionHeader(title: "Código de invitación", systemImage: "ticket")
                        HomitaField(placeholder: "Código (opcional)", text: $invitationCode, isCode: true)
                        HomitaFootnote(text: "Si te invitaron a un hogar, usa el email de la invitación. Sin código, se crea una cuenta nueva.")
                    }
                }
                HomitaPrimaryButton(title: "Crear cuenta", isEnabled: isValid, isLoading: isWorking) {
                    Task { await register() }
                }
                .homitaRequiresNetwork()
                .accessibilityIdentifier("registro.crear-cuenta")
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Registrarse")
        .homitaNavigationBar()
        .errorAlert($errorMessage)
        .navigationDestination(isPresented: $showLogin) {
            LoginView(services: services, email: email.trimmingCharacters(in: .whitespaces),
                      password: password, notice: RegistrationOutcome.needsLoginNotice)
        }
        .overlay {
            if isWorking {
                HomitaLoadingOverlay(message: "Creando cuenta…")
            }
        }
        .disabled(isWorking)
    }

    private var isValid: Bool {
        name.codepointCount >= 3 && name.codepointCount <= 50
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.codepointCount >= 8
            && (invitationCode.trimmingCharacters(in: .whitespaces).isEmpty || InvitationCode.isValid(invitationCode))
    }

    private func register() async {
        isWorking = true
        defer { isWorking = false }
        let code = invitationCode.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : InvitationCode.normalize(invitationCode)
        do {
            let outcome = try await services.auth.register(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                invitationCode: code
            )
            // La cuenta ya existe: la invitación queda pendiente en memoria hasta aceptarla tras el
            // login (con sesión, NoHomeView la acepta sola).
            services.homeContext.pendingInvitationCode = code
            if outcome == .needsLogin { showLogin = true }
        } catch {
            errorMessage = Self.registerMessage(for: error)
        }
    }

    /// Mensajes de registro con código (0023). El resto usa el mensaje genérico de `APIError`.
    static func registerMessage(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .http(status: 404, message: "Invitation code is not valid"):
                return "El código de invitación no es válido, ya se usó o ha caducado"
            case .http(status: 403, message: "The invitation was sent to another email address"):
                return "La invitación se envió a otro email. Usa el email de la invitación"
            case .http(status: 400, message: "Email already exists"):
                return "Ya tienes cuenta: inicia sesión y acepta la invitación desde Ajustes"
            default:
                return api.userMessage
            }
        }
        return error.localizedDescription
    }
}
