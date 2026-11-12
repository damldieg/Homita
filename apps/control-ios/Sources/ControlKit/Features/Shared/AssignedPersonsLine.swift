import SwiftUI

/// Línea «Para: Ana, Luis» con las personas asignadas de un evento o rutina (A2). No se muestra
/// si no hay asignados.
struct AssignedPersonsLine: View {
    let persons: [PersonEntry]?

    var body: some View {
        if let names = persons?.map(\.name), !names.isEmpty {
            Text("Para: \(names.joined(separator: ", "))")
                .font(HomitaFont.geist(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(2)
        }
    }
}

/// Personas asignadas como etiquetas de color (`HomitaBadge` con el color de cada persona).
/// No se muestra si no hay asignados.
struct AssignedPersonTags: View {
    let persons: [PersonEntry]?

    var body: some View {
        if let persons, !persons.isEmpty {
            HStack(spacing: 6) {
                ForEach(persons, id: \.id) { person in
                    HomitaBadge(title: person.name, tintHex: person.color)
                }
            }
        }
    }
}
