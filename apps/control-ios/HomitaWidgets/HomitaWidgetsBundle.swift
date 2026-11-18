import SwiftUI
import WidgetKit

/// Extensión de widgets de Homita: Rutinas de hoy, Accesos rápidos, Nueva tarea/evento/rutina y la Live Activity de rutinas.
@main
struct HomitaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RoutinesWidget()
        QuickActionsWidget()
        NewTaskWidget()
        NewEventWidget()
        NewRoutineWidget()
        RoutineLiveActivity()
    }
}
