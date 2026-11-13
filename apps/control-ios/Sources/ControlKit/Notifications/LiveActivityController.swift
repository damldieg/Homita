import Foundation
import HomitaShared

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// Live Activity de rutinas en la pantalla de bloqueo y la Dynamic Island.
///
/// Se inicia o actualiza cuando la app está abierta (iOS solo permite arrancarla en primer plano
/// sin notificaciones push) y, ya en marcha, la cuenta atrás y la barra de tiempo las anima el
/// sistema sin gastar batería. Se termina sola al acabar la ventana de la rutina o al cerrar la app
/// si ya no hay nada en curso.
@MainActor
enum LiveActivityController {
    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func sync(snapshot: HomitaSnapshot?, preferences: NotificationPreferences, now: Date = Date()) async {
        let existing = Activity<RoutineActivityAttributes>.activities
        guard preferences.routineLiveActivity, let snapshot, snapshot.signedIn, !snapshot.isStale(at: now),
              let state = snapshot.liveActivityState(at: now) else {
            await end(existing)
            return
        }
        // Tras el fin de la ventana la actividad queda «obsoleta»: la vista muestra «Finalizada».
        let content = ActivityContent(state: state, staleDate: state.progressEnd)
        if let current = existing.first {
            await end(Array(existing.dropFirst()))
            await current.update(content)
        } else if isAvailable {
            // Falla si la app no está en primer plano; se reintenta en la siguiente sincronización.
            _ = try? Activity.request(
                attributes: RoutineActivityAttributes(homeName: snapshot.homeName ?? "Homita"),
                content: content, pushType: nil
            )
        }
    }

    static func endAll() async {
        await end(Activity<RoutineActivityAttributes>.activities)
    }

    private static func end(_ activities: [Activity<RoutineActivityAttributes>]) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#else
@MainActor
enum LiveActivityController {
    static func sync(snapshot: HomitaSnapshot?, preferences: NotificationPreferences, now: Date = Date()) async {}
    static func endAll() async {}
}
#endif
