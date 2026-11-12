import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit
#endif

/// Carga del hogar activo: solo esqueleto con la forma de una pantalla (sin spinner ni texto).
struct HomeLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s5) {
            HomitaSkeletonBlock(height: 40)
                .frame(maxWidth: 220)
            HomitaSkeletonBlock(height: 18)
                .frame(maxWidth: 140)
            HomitaSkeletonRows(count: 3, height: 64, label: "Cargando hogar")
        }
        .padding(Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.ignoresSafeArea())
    }
}

/// Fallo al resolver el hogar, con reintento.
struct HomeErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HomitaPanel("No se pudo cargar tu hogar", systemImage: "exclamationmark.triangle", tint: Palette.accent) {
            Text(message)
                .font(HomitaFont.inter(15, relativeTo: .body))
                .foregroundStyle(Palette.inkSoft)
            HomitaButton(title: "Reintentar", action: retry)
        }
    }
}
