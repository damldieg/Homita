import Foundation
import HomitaShared
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// Punto de entrada de la plataforma al arrancar: delegado de notificaciones y refresco en segundo
/// plano. Lo llama `ControlApp.init()`; BGTaskScheduler exige registrar el manejador antes de que
/// termine el arranque, por eso no puede esperar a `RootView`.
public enum HomitaPlatform {
    /// Identificador de la tarea (también en `BGTaskSchedulerPermittedIdentifiers` del Info.plist).
    public static let refreshTaskId = "com.lito.planify.control.ios.refresh"

    @MainActor
    public static func didLaunch() {
        #if os(iOS)
        UNUserNotificationCenterBridge.install()
        BackgroundRefresh.register()
        #endif
    }
}

#if os(iOS)
import UserNotifications

enum UNUserNotificationCenterBridge {
    @MainActor
    static func install() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }
}

/// Refresco en segundo plano (`BGAppRefreshTask`): el sistema decide cuándo; sirve para que los
/// avisos, los widgets y la Live Activity no dependan de abrir la app cada día.
enum BackgroundRefresh {
    @MainActor
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: HomitaPlatform.refreshTaskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(task)
        }
    }

    /// Pide la próxima ejecución (≥ 30 min); se llama al pasar a segundo plano y al terminar.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: HomitaPlatform.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            // Si la app ya está abierta, `HomitaSync.shared` tiene sus servicios; si el sistema la
            // lanzó solo para esto, se crean unos propios con la sesión del Keychain.
            let sync = HomitaSync.shared
            if !sync.isAttached {
                let services = AppServices.makeBackground()
                await services.homeContext.load(using: services.homes)
                sync.attach(services)
            }
            await sync.refresh(force: true, allowPrompt: false)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
