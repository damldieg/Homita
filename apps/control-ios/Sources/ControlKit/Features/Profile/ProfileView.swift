import SwiftUI

/// Perfil: datos de cuenta (`PATCH user/update`: nombre, email y contraseña opcional), acceso a
/// Personas, unirse a un hogar con un código de invitación (1.15) y cierre de sesión (local: no
/// hay endpoint de revocación).
public struct ProfileView: View {
    let services: AppServices

    @State private var personStore: PersonStore
    @State private var didLoadPersons = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    public init(services: AppServices) {
        self.services = services
        _personStore = State(initialValue: PersonStore(repo: services.persons))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    TextField("Nombre", text: $name)
                    EmailTextField(prompt: "Email", text: $email)
                    SecureField("Nueva contraseña (opcional, mínimo 8)", text: $password)
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Guardar cambios")
                        }
                    }
                    .disabled(!isValid || isWorking)
                }
                Section("Familia") {
                    NavigationLink {
                        PersonsView(store: personStore)
                    } label: {
                        Label("Personas", systemImage: "person.2")
                    }
                }
                // 1.15 (D-016): fuera del `if case .ready`, visible también sin hogar activo.
                Section("Invitaciones") {
                    NavigationLink {
                        AcceptInvitationView(services: services)
                    } label: {
                        Label("Unirse a un hogar con un código", systemImage: "person.badge.plus")
                    }
                }
                if !services.homeContext.homes.isEmpty {
                    Section {
                        ForEach(HomeSwitcher.rows(homes: services.homeContext.homes,
                                                  activeHomeId: services.homeContext.activeHomeId)) { row in
                            Button {
                                services.homeContext.select(homeId: row.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(row.name).foregroundStyle(.primary)
                                        Text(row.roleLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if row.isActive {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityAddTraits(row.isActive ? .isSelected : [])
                        }
                    } header: {
                        Text("Mis hogares")
                    } footer: {
                        if let error = services.homeContext.persistenceError {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }
                if case .ready(let home) = services.homeContext.state {
                    Section("Hogar") {
                        NavigationLink {
                            HomeAdminView(services: services, home: home)
                        } label: {
                            Label("Administración del hogar", systemImage: "house")
                        }
                    }
                }
                Section {
                    Button("Cerrar sesión", role: .destructive) {
                        services.signOut()
                    }
                } footer: {
                    Text("Con firma gratuita la app caduca a los 7 días; reinstálala y vuelve a iniciar sesión.")
                }
            }
            .navigationTitle("Perfil")
            .errorAlert($errorMessage)
            .onAppear {
                name = services.session.session?.name ?? ""
                email = services.session.session?.email ?? ""
                // Personas: carga al aparecer la pestaña (una vez, sin bloquear); el refresco
                // manual queda en PersonsView (.refreshable).
                if !didLoadPersons {
                    didLoadPersons = true
                    Task { await personStore.load() }
                }
            }
        }
    }

    private var isValid: Bool {
        name.codepointCount >= 3 && name.codepointCount <= 50
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && (password.isEmpty || password.codepointCount >= 8)
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.updateProfile(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password.isEmpty ? nil : password
            )
            password = ""
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}
