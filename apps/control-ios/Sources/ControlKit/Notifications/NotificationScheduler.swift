import Foundation
import HomitaShared
import UserNotifications

/// Estado del permiso de notificaciones del sistema.
public enum NotificationPermission: Equatable, Sendable {
    case notDetermined, denied, allowed
}

/// Parte mínima de `UNUserNotificationCenter` que usa el scheduler (permite probarlo con un centro falso).
public protocol NotificationCenterProtocol {
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllDeliveredNotifications()
}

extension UNUserNotificationCenter: NotificationCenterProtocol {}

/// Centro sin efecto para procesos sin bundle de app (tests).
private struct NoopNotificationCenter: NotificationCenterProtocol {
    func add(_ request: UNNotificationRequest) async throws {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeAllDeliveredNotifications() {}
}

/// Envoltorio de `UNUserNotificationCenter`: pide permiso, sustituye los avisos pendientes por los
/// nuevos y los borra al cerrar sesión. Solo toca las notificaciones propias (`homita.*`).
public struct NotificationScheduler {
    static let idPrefix = "homita."

    private let injected: NotificationCenterProtocol?

    /// Centro de notificaciones; por defecto el del sistema (`UNUserNotificationCenter.current()`).
    public init(center: NotificationCenterProtocol? = nil) {
        self.injected = center
    }

    /// Fuera de un `.app`/`.appex` (p. ej. el host `xctest` de `swift test`) `UNUserNotificationCenter.current()`
    /// lanza una `NSInternalInconsistencyException` (bundleProxy nil) que, desde un `Task` suelto
    /// (`signOut` → `HomitaSync.reset`), aborta el proceso. Allí se usa un centro vacío.
    private var center: NotificationCenterProtocol {
        if let injected { return injected }
        let ext = Bundle.main.bundleURL.pathExtension
        guard ext == "app" || ext == "appex" else { return NoopNotificationCenter() }
        return UNUserNotificationCenter.current()
    }

    public func permission() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Pide el permiso (solo muestra el diálogo si aún no se decidió). Devuelve si quedó permitido.
    @discardableResult
    public func requestPermission() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    /// Sustituye los avisos **pendientes** propios por `planned`. Los ya entregados se dejan en el
    /// panel de notificaciones, como hace Calendario: no se tocan en cada sincronización.
    public func replaceAll(with planned: [PlannedNotification], timeZone: TimeZone = .current) async {
        let center = self.center
        await removePending()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            // Suena (tono de aviso por defecto), sale como banner y queda en el panel.
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = "homita.\(item.kind.rawValue)"
            content.userInfo = [NotificationRouter.linkKey: item.link.url.absoluteString]
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// Borra los avisos pendientes propios (los entregados siguen en el panel).
    public func removePending() async {
        let center = self.center
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        )
    }

    /// Borra pendientes y entregados (cierre de sesión: nada del usuario anterior en el panel).
    public func removeAll() async {
        await removePending()
        center.removeAllDeliveredNotifications()
    }

    /// Programa (o sustituye) el resumen diario: un único aviso recurrente a `hour:minute` hora local.
    /// Mismo identificador = sustituye; nunca quedan dos. No fija zona en los componentes: sigue la del sistema.
    public func scheduleDailySummary(_ summary: DailySummary, hour: Int, minute: Int) async {
        let center = self.center
        center.removePendingNotificationRequests(withIdentifiers: [DailySummaryPlanner.identifier])
        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = DailySummaryPlanner.identifier
        content.userInfo = [NotificationRouter.linkKey: summary.link.url.absoluteString]
        var parts = DateComponents()
        parts.hour = min(max(hour, 0), 23)
        parts.minute = min(max(minute, 0), 59)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: DailySummaryPlanner.identifier, content: content, trigger: trigger))
    }

    /// Borra el resumen diario pendiente (si lo hay).
    public func removeDailySummary() async {
        center.removePendingNotificationRequests(withIdentifiers: [DailySummaryPlanner.identifier])
    }
}

/// Delegado de notificaciones: las muestra aunque la app esté abierta y, al tocarlas, abre su destino.
public final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationRouter()
    static let linkKey = "link"

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo[Self.linkKey] as? String,
           let link = HomitaDeepLink(string: raw) {
            Task { @MainActor in DeepLinkCenter.shared.open(link) }
        }
        completionHandler()
    }
}
