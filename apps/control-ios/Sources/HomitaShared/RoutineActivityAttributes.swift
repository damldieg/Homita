#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity «Rutinas»: muestra en la pantalla de bloqueo la rutina en curso o la próxima
/// (a menos de una hora), con cuenta atrás y barra de tiempo del propio sistema.
public struct RoutineActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Phase: String, Codable, Hashable {
            case soon
            case now
        }

        public var title: String
        public var colorHex: String
        public var phase: Phase
        public var start: Date
        public var end: Date
        public var doneCount: Int
        public var totalCount: Int
        public var nextTitle: String?
        public var nextStart: Date?

        public init(
            title: String, colorHex: String, phase: Phase, start: Date, end: Date,
            doneCount: Int, totalCount: Int, nextTitle: String? = nil, nextStart: Date? = nil
        ) {
            self.title = title
            self.colorHex = colorHex
            self.phase = phase
            self.start = start
            self.end = end
            self.doneCount = doneCount
            self.totalCount = totalCount
            self.nextTitle = nextTitle
            self.nextStart = nextStart
        }

        /// Inicio del tramo que recorre la barra: la hora previa al inicio (aviso) o el inicio (en curso).
        public var progressStart: Date {
            phase == .soon ? start.addingTimeInterval(-HomitaShared.routineSoonWindow) : start
        }

        /// Fin del tramo de la barra: el inicio (aviso) o el fin de la ventana (en curso).
        public var progressEnd: Date { phase == .soon ? start : end }
    }

    public var homeName: String

    public init(homeName: String) {
        self.homeName = homeName
    }
}

extension HomitaSnapshot {
    /// Contenido de la Live Activity a la hora `now`: la rutina en curso o en aviso. `nil` si no
    /// hay ninguna (entonces la actividad se termina).
    public func liveActivityState(at now: Date) -> RoutineActivityAttributes.ContentState? {
        guard let focus = focusRoutine(at: now), let start = focus.start, let end = focus.end else { return nil }
        let phase = focus.phase(at: now)
        let state: RoutineActivityAttributes.ContentState.Phase
        switch phase {
        case .now: state = .now
        case .soon: state = .soon
        default: return nil
        }
        let next = routine(after: focus, at: now)
        return RoutineActivityAttributes.ContentState(
            title: focus.title, colorHex: focus.colorHex, phase: state, start: start, end: end,
            doneCount: doneCount(at: now), totalCount: routines.count,
            nextTitle: next?.title, nextStart: next?.start
        )
    }
}
#endif
