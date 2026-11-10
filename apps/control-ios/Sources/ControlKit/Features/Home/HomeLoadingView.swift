import SwiftUI

/// Carga del hogar activo.
struct HomeLoadingView: View {
    var body: some View {
        ProgressView("Cargando hogar…")
    }
}

/// Fallo al resolver el hogar, con reintento.
struct HomeErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("No se pudo cargar tu hogar")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reintentar", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
