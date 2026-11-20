import SwiftUI

/// Banda bajo la barra de estado cuando no hay red o se muestran datos de caché (E0-06, punto 4):
/// «Sin conexión. Mostrando datos de las 19:12.» con «Reintentar». Desaparece al recuperar la red.
/// Con cambios en la cola offline (D-024) añade «N cambios pendientes» y, con red, sigue visible
/// hasta que la cola se vacía; «Reintentar» recarga y además reproduce la cola.
struct HomitaOfflineBanner: View {
    let freshness: DataFreshness
    var pendingCount: Int = 0
    var onRetry: () -> Void = {}

    var body: some View {
        if let text = message {
            HStack(spacing: Spacing.s3) {
                Image(systemName: freshness.isOffline || freshness.staleSince != nil ? "wifi.slash" : "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.warn)
                Text(text)
                    .font(HomitaFont.inter(14, weight: .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Reintentar") {
                    freshness.requestReload()
                    onRetry()
                }
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
        Self.message(isOffline: freshness.isOffline, staleSince: freshness.staleSince, pendingCount: pendingCount)
    }

    /// Texto del banner (función pura, AC8); `nil` = sin banner.
    static func message(isOffline: Bool, staleSince: Date?, pendingCount: Int) -> String? {
        let pending = pendingCount > 0 ? " \(pendingText(pendingCount))." : ""
        if let since = staleSince {
            return "Sin conexión. Mostrando datos de las \(time(since)).\(pending)"
        }
        if isOffline {
            return "Sin conexión.\(pending)"
        }
        if pendingCount > 0 {
            return "\(pendingText(pendingCount)) de sincronizar"
        }
        return nil
    }

    /// «1 cambio pendiente» / «N cambios pendientes».
    static func pendingText(_ count: Int) -> String {
        count == 1 ? "1 cambio pendiente" : "\(count) cambios pendientes"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
