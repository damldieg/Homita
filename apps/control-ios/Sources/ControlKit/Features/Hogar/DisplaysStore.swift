import Foundation

/// Estado de la sección «Pantallas» de Hogar: lista, vincular con código, editar y revocar. Con la guarda `isActive`
/// (patrón de `HogarStore`) una respuesta de otro hogar no pisa el estado.
@Observable
public final class DisplaysStore {
    public private(set) var displays: [HomeDisplay] = []
    public private(set) var state: HomeAdminLoadState = .idle
    /// Mensaje del último intento de vincular, editar o revocar (vacío si fue bien).
    public private(set) var lastError: String?

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?

    public init(repo: HomeRepository, homeId: Int, activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.homeId = homeId
        self.activeHomeId = activeHomeId
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let list = try await repo.displays(homeId: homeId)
            guard isActive else { return }
            displays = list
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    /// Vincula la pantalla que muestra el código. Devuelve true si se vinculó (y recarga la lista).
    @discardableResult
    public func link(code: String, name: String) async -> Bool {
        do {
            _ = try await repo.confirmDisplayLink(code: code.filter(\.isNumber), name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            lastError = nil
            await load()
            return true
        } catch {
            lastError = linkMessage(error)
            return false
        }
    }

    /// Guarda nombre, ajustes y selección de una pantalla. Lo que no cambia se envía igual (el servidor guarda el objeto).
    public func save(display: HomeDisplay, name: String, settings: DisplaySettings,
                     calendarIds: [Int], taskListIds: [Int]) async {
        do {
            let updated = try await repo.updateDisplay(UpdateDisplayBody(
                id: display.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), settings: settings,
                calendarIds: calendarIds, taskListIds: taskListIds))
            lastError = nil
            guard isActive else { return }
            displays = displays.map { $0.id == updated.id ? updated : $0 }
        } catch {
            lastError = homeAdminMessage(error)
        }
    }

    /// Revoca la pantalla: deja de leer el hogar y vuelve a la pantalla de vinculación.
    public func revoke(_ display: HomeDisplay) async {
        do {
            _ = try await repo.revokeDisplay(id: display.id)
            lastError = nil
            await load()
        } catch {
            lastError = homeAdminMessage(error)
        }
    }

    /// Mensajes de la vinculación. Código incorrecto o caducado, límite de intentos y de pantallas.
    private func linkMessage(_ error: Error) -> String {
        // El mensaje del servidor (sin traducir) decide el texto; si no hay, el genérico de la app
        let serverMessage: String? = {
            if case .http(_, let message)? = error as? APIError { return message }
            return nil
        }()
        switch serverMessage ?? "" {
        case "Invalid link code": return "El código no es válido o ha caducado. Mira la pantalla y escribe el que aparece."
        case "Too many attempts": return "Demasiados intentos. Espera unos minutos."
        case "Display limit reached": return "El hogar ya tiene 5 pantallas. Revoca una para vincular otra."
        default: return homeAdminMessage(error)
        }
    }
}
