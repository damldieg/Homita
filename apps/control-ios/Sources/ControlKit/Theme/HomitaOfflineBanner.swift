import SwiftUI

/// Banda bajo la barra de estado cuando no hay red o se muestran datos de caché (E0-06, punto 4):
/// «Sin conexión. Mostrando datos de las 19:12.» con «Reintentar». Desaparece al recuperar la red.
struct HomitaOfflineBanner: View {
    let freshness: DataFreshness

    var body: some View {
        if let text = message {
            HStack(spacing: Spacing.s3) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.warn)
                Text(text)
                    .font(HomitaFont.inter(14, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Reintentar") { freshness.requestReload() }
                    .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .background(Palette.warnSoft, in: RoundedRectangle(cornerRadius: Radius.md))
            .padding(.horizontal, Spacing.s4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Texto del banner según el estado; `nil` = sin banner.
    var message: String? {
        if let since = freshness.staleSince {
            return "Sin conexión. Mostrando datos de las \(Self.time(since))."
        }
        if freshness.isOffline {
            return "Sin conexión."
        }
        return nil
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
