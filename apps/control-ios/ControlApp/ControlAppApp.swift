import SwiftUI
import ControlKit

/// Entry point de la app (guía README «Instalar en el iPhone», paso 3):
/// `WindowGroup { RootView() }` — toda la UI y la lógica viven en ControlKit.
@main
struct ControlApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
