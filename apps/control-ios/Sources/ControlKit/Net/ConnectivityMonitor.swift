import Foundation
import Network

/// Vigila la red con `NWPathMonitor` y actualiza `DataFreshness` (E0-06, punto 3).
/// Una sola instancia por proceso.
public final class ConnectivityMonitor: @unchecked Sendable {
    public static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private var started = false
    private let lock = NSLock()

    private init() {}

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let offline = path.status != .satisfied
            Task { @MainActor in DataFreshness.shared.setOffline(offline) }
        }
        monitor.start(queue: DispatchQueue(label: "ControlKit.connectivity"))
    }
}
