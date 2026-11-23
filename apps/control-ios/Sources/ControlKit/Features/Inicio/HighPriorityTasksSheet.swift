import SwiftUI

/// Lista de tareas de prioridad alta pendientes (propias y del hogar sin asignar), agrupadas por lista.
/// Se abre desde «Ver más» del resumen de Inicio.
struct HighPriorityTasksSheet: View {
    let groups: [TaskListGroup]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    Text("No hay tareas de prioridad alta pendientes.")
                        .foregroundStyle(Palette.inkSoft)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            Text(task.title)
                                .font(HomitaFont.inter(15, weight: .medium, relativeTo: .body))
                                .foregroundStyle(Palette.ink)
                        }
                    } header: {
                        Text(group.name)
                    }
                }
            }
            .navigationTitle("Prioridad alta")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
