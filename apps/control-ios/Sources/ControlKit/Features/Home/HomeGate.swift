import SwiftUI

/// Puerta de las pestañas de contenido: el contenido real solo se instancia con hogar activo
/// (`.ready`); en cualquier otro estado no se hace ninguna llamada que requiera hogar.
struct HomeGate<Content: View>: View {
    let services: AppServices
    let state: HomeContextState
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch state {
        case .ready:
            content()
        case .unresolved, .loading:
            HomeLoadingView()
        case .noHome:
            NoHomeView(services: services)
        case .failed(let message):
            HomeErrorView(message: message) {
                Task { await services.homeContext.load(using: services.homes) }
            }
        }
    }
}
