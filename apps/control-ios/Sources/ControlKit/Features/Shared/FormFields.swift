import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit
#endif

/// Valores de alarma del contrato: `null` (sin aviso) | 0 | 10 | 20 | 30 | 40 | 60 minutos.
/// En v1 solo se guardan en el servidor: el iPhone no programa avisos (README).
enum AlarmOption {
    static let minutes = [0, 10, 20, 30, 40, 60]

    static func label(_ minutes: Int) -> String {
        minutes == 0 ? "Justo antes" : "\(minutes) min antes"
    }
}

/// Aviso de evento/rutina con `SURadioGroup`. «Sin aviso» se codifica como -1 en el selector.
struct AlarmField: View {
    @Binding var alarm: Int?

    private static let noAlarm = -1

    var body: some View {
        HomitaPanel("Aviso", systemImage: "bell") {
            HomitaRadioGroup(
                selection: Binding(
                    get: { alarm ?? Self.noAlarm },
                    set: { alarm = ($0 == Self.noAlarm) ? nil : $0 }
                ),
                items: [(id: Self.noAlarm, title: "Sin aviso")] + AlarmOption.minutes.map { (id: $0, title: AlarmOption.label($0)) }
            )
            HomitaFootnote(text: "La alarma se guarda en el servidor. El aviso en este iPhone llegará con las notificaciones (fase 3).")
        }
    }
}

/// Selector múltiple de personas asignadas (eventos y rutinas), con casillas de Homita.
struct PersonSelector: View {
    let persons: [PersonEntry]
    @Binding var selected: [Int]

    var body: some View {
        HomitaPanel("Personas", systemImage: "person.2", count: selected.count) {
            if persons.isEmpty {
                HomitaFootnote(text: "Aún no tienes personas. Créalas en Ajustes › Personas.")
            }
            ForEach(persons, id: \.id) { person in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: person.color))
                        .frame(width: 14, height: 14)
                    Text(person.name)
                        .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    HomitaCheckbox(isOn: selected.contains(person.id), tintHex: person.color) {
                        if selected.contains(person.id) {
                            selected.removeAll { $0 == person.id }
                        } else {
                            selected.append(person.id)
                        }
                    }
                }
            }
        }
    }
}

/// Campo de email (sin autocapitalización ni autocorrección): `HomitaField` con `SUInputField`.
struct EmailTextField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HomitaField(placeholder: prompt, text: $text, isEmail: true)
    }
}

/// Miembros compartidos: permiso de cada persona con cuenta, invitación por email y retirada.
/// El owner ve un selector Lectura/Edición por persona (también para las cuentas del hogar que aún
/// no tienen acceso); el resto ve solo su permiso. Todo es owner-only también en el servidor
/// (403 `Not Allowed` → toast), la app solo oculta lo que no puede usar.
struct MembersSection: View {
    let rows: [AccessRow]
    let isOwner: Bool
    let onSetAccess: (Int, AccessLevel) -> Void
    var showsInvites = true
    let onInvite: (String) -> Void
    let onRemove: (Int) -> Void

    @State private var inviteEmail = ""

    var body: some View {
        HomitaPanel("Personas con acceso", systemImage: "person.badge.key", count: rows.filter(\.hasAccess).count) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                        if let email = row.email {
                            Text(email)
                                .font(HomitaFont.inter(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSoft)
                        } else {
                            Text("Sin acceso")
                                .font(HomitaFont.inter(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    Spacer()
                    if row.isEditable {
                        accessMenu(for: row)
                    } else if let level = row.level {
                        HomitaBadge(title: level.title,
                                    tintHex: level == .owner ? Palette.accentHex : Palette.inkSoftHex)
                    }
                    if showsInvites && isOwner && row.hasAccess && row.isEditable {
                        Button {
                            onRemove(row.userId)
                        } label: {
                            Image(systemName: "person.badge.minus")
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if showsInvites && isOwner {
                HomitaField(placeholder: "Email a invitar", text: $inviteEmail, isEmail: true)
                HomitaButton(
                    title: "Invitar",
                    kind: .secondary,
                    isEnabled: !inviteEmail.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    let email = inviteEmail.trimmingCharacters(in: .whitespaces)
                    guard !email.isEmpty else { return }
                    onInvite(email)
                    inviteEmail = ""
                }
            }
        }
    }

    /// Selector de permiso de una fila (Lectura/Edición). Sin acceso muestra «Dar acceso».
    private func accessMenu(for row: AccessRow) -> some View {
        Menu {
            ForEach(AccessLevel.choices, id: \.self) { level in
                Button {
                    if row.level != level { onSetAccess(row.userId, level) }
                } label: {
                    if row.level == level {
                        Label(level.title, systemImage: "checkmark")
                    } else {
                        Text(level.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(row.level?.title ?? "Dar acceso")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(HomitaFont.inter(15, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(row.hasAccess ? Palette.ink : Palette.accent)
        }
        .accessibilityIdentifier("acceso.permiso.\(row.userId)")
    }
}

extension View {
    /// Alerta genérica para los errores de los stores (`errorMessage`): `SUAlert` de ComponentsKit
    /// en iOS, alerta de sistema en macOS.
    func errorAlert(_ message: Binding<String?>) -> some View {
        let isPresented = Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
        #if canImport(ComponentsKit)
        return self.suAlert(isPresented: isPresented, model: errorAlertModel(message.wrappedValue ?? ""))
        #else
        return alert("Aviso", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
        #endif
    }
}

#if canImport(ComponentsKit)
/// Modelo de la alerta de error de Homita (título «Aviso», botón «OK»).
private func errorAlertModel(_ text: String) -> AlertVM {
    AlertVM {
        $0.title = "Aviso"
        $0.message = text
        $0.primaryButton = AlertButtonVM { $0.title = "OK" }
    }
}
#endif
