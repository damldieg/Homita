import SwiftUI

/// Estado sin hogar: permite crear el primero (`POST home/create`).
struct NoHomeView: View {
    let services: AppServices
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 12) {
            Text("No tienes ningún hogar")
                .font(.headline)
            Text("Crea uno para empezar a usar tareas y calendarios.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Nombre del hogar", text: $name)
                .textFieldStyle(.roundedBorder)
            Button {
                Task {
                    isWorking = true
                    errorMessage = await services.homeContext.create(name: trimmed, using: services.homes)
                    isWorking = false
                }
            } label: {
                if isWorking { ProgressView() } else { Text("Crear hogar") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmed.isEmpty || isWorking)
        }
        .padding()
        .errorAlert($errorMessage)
    }
}
