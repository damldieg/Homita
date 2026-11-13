import SwiftUI

/// Cabecera estándar de pestaña (E0-02): título grande pegado al borde superior, subtítulo
/// opcional y hasta dos acciones circulares de 44 pt. Sustituye al título dentro del contenido
/// y a la barra de navegación vacía, que dejaba un hueco.
struct HomitaHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(HomitaFont.inter(34, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(HomitaFont.inter(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s2) {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.s2)
    }
}

extension HomitaHeader where Actions == EmptyView {
    /// Cabecera sin acciones.
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, actions: { EmptyView() })
    }
}

/// Botón circular de la cabecera: 44 pt, icono y etiqueta de accesibilidad.
struct HomitaHeaderButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Reglas de la cabecera que no dependen de la vista (testables).
enum HomitaHeaderLayout {
    /// Máximo de acciones circulares en una cabecera.
    static let maxActions = 2

    /// Número de acciones que se muestran: nunca negativo ni más de `maxActions`.
    static func visibleActionCount(_ requested: Int) -> Int {
        min(max(requested, 0), maxActions)
    }
}
