import SwiftUI

/// Valores de alarma del contrato: `null` (sin aviso) | 0 | 10 | 20 | 30 | 40 | 60 minutos.
/// En v1 solo se guardan en el servidor: el iPhone no programa avisos (README).
enum AlarmOption {
    static let minutes = [0, 10, 20, 30, 40, 60]

    static func label(_ minutes: Int) -> String {
        minutes == 0 ? "Justo antes" : "\(minutes) min antes"
    }
}

struct AlarmField: View {
    @Binding var alarm: Int?

    var body: some View {
        Picker("Aviso", selection: $alarm) {
            Text("Sin aviso").tag(Int?.none)
            ForEach(AlarmOption.minutes, id: \.self) { minutes in
                Text(AlarmOption.label(minutes)).tag(Int?.some(minutes))
            }
        }
        Text("La alarma se guarda en el servidor; el iPhone no avisará en v1.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Selector múltiple de personas asignadas (eventos y rutinas).
struct PersonSelector: View {
    let persons: [PersonEntry]
    @Binding var selected: [Int]

    var body: some View {
        Section("Personas") {
            ForEach(persons, id: \.id) { person in
                Button {
                    if selected.contains(person.id) {
                        selected.removeAll { $0 == person.id }
                    } else {
                        selected.append(person.id)
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: person.color))
                            .frame(width: 12, height: 12)
                        Text(person.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selected.contains(person.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
    }
}

/// Campo de email sin autocapitalización ni autocorrección (iOS) / plano en macOS.
struct EmailTextField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        #if os(iOS)
        TextField(prompt, text: $text)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField(prompt, text: $text)
        #endif
    }
}

/// Miembros compartidos: invitación por email y retirada. Las acciones son owner-only (rol del
/// propio usuario en el payload de miembros, `role`); la fila propia nunca muestra acciones. El
/// servidor sigue aplicando 403/400 como última barrera.
struct MembersSection: View {
    let members: [MemberEntry]
    let currentUserId: Int?
    let onInvite: (String) -> Void
    let onRemove: (Int) -> Void

    @State private var inviteEmail = ""

    /// Dueño según el payload de miembros: la fila del usuario actual (`role == "owner"`).
    private var isOwner: Bool {
        members.first { $0.user_id == currentUserId }?.isOwner ?? false
    }

    var body: some View {
        Section("Personas con acceso") {
            ForEach(members, id: \.id) { member in
                HStack {
                    VStack(alignment: .leading) {
                        Text(member.name)
                        Text(member.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(member.isOwner ? "Propietario" : "Solo lectura")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isOwner && member.user_id != currentUserId {
                        Button(role: .destructive) {
                            onRemove(member.user_id)
                        } label: {
                            Image(systemName: "person.badge.minus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if isOwner {
                HStack {
                    EmailTextField(prompt: "Email a invitar", text: $inviteEmail)
                    Button("Invitar") {
                        let email = inviteEmail.trimmingCharacters(in: .whitespaces)
                        guard !email.isEmpty else { return }
                        onInvite(email)
                        inviteEmail = ""
                    }
                    .disabled(inviteEmail.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension View {
    /// Alerta genérica para los errores de los stores (`errorMessage`).
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Aviso",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
