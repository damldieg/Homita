import SwiftUI

/// Personas asignadas: avatar con la inicial en su color y el nombre al lado (wireframe, «av» + nombre).
/// No se muestra si no hay asignados.
struct AssignedPersonsLine: View {
    let persons: [PersonEntry]?

    var body: some View {
        if let persons, !persons.isEmpty {
            HStack(spacing: Spacing.s3) {
                ForEach(persons, id: \.id) { person in
                    HStack(spacing: Spacing.s1) {
                        PersonAvatar(name: person.name, colorHex: person.color, size: 18)
                        Text(person.name)
                            .font(HomitaFont.inter(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Personas asignadas en Tareas: mismo formato que `AssignedPersonsLine`.
struct AssignedPersonTags: View {
    let persons: [PersonEntry]?

    var body: some View {
        AssignedPersonsLine(persons: persons)
    }
}

/// Avatar circular con la inicial de la persona sobre su color. El texto es blanco o tinta según
/// la luminancia del color, para que se lea en claro y en oscuro (E1-07).
struct PersonAvatar: View {
    let name: String
    let colorHex: String
    var size: CGFloat = 20

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Self.labelColor(on: colorHex))
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }

    /// Blanco sobre colores oscuros, tinta sobre los claros (luminancia relativa WCAG).
    static func labelColor(on hex: String) -> Color {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        func channel(_ shift: UInt64) -> Double {
            let c = Double((value >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        return luminance > 0.35 ? Palette.ink : Color.white
    }
}
