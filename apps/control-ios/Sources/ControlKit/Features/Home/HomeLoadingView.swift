import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit
#endif

/// Carga del hogar activo.
struct HomeLoadingView: View {
    var body: some View {
        HomitaCard {
            HStack(spacing: 12) {
                #if canImport(ComponentsKit)
                SULoading(model: LoadingVM { $0.color = ComponentColor(main: uc(Palette.accentHex), contrast: uc("#FFFFFF")) })
                #else
                ProgressView()
                #endif
                Text("Cargando hogar…")
                    .font(HomitaFont.geist(16, relativeTo: .body))
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Fallo al resolver el hogar, con reintento.
struct HomeErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HomitaPanel("No se pudo cargar tu hogar", systemImage: "exclamationmark.triangle", tint: Palette.accent) {
            Text(message)
                .font(HomitaFont.geist(15, relativeTo: .body))
                .foregroundStyle(Palette.inkSoft)
            HomitaButton(title: "Reintentar", action: retry)
        }
    }
}
