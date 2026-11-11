import SwiftUI

/// Estado sin hogar: permite crear el primero (`POST home/create`).
struct NoHomeView: View {
    let services: AppServices
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HomitaForm {
            HomitaPanel("No tienes ningún hogar", systemImage: "house") {
                HomitaFootnote(text: "Crea uno para empezar a usar tareas y calendarios.")
                HomitaField(placeholder: "Nombre del hogar", text: $name)
            }
            HomitaPrimaryButton(title: "Crear hogar", isEnabled: !trimmed.isEmpty && !isWorking, isLoading: isWorking) {
                Task {
                    isWorking = true
                    errorMessage = await services.homeContext.create(name: trimmed, using: services.homes)
                    isWorking = false
                }
            }
        }
        .errorAlert($errorMessage)
    }
}
