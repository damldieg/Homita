import Foundation

/// Compactación de la cola offline al encolar (D-024). Función pura: recibe la cola, la op nueva y
/// la op en vuelo (inmutable: lo que llega sobre ella se añade al final y se resuelve con el ack).
///
/// Reglas:
/// - Update sobre un create pendiente: se funde en el create (título nuevo; `personIds` y `priority`
///   del update o, si son nil, los del create).
/// - Update sobre otro update del mismo recurso: queda el último, con la misma regla de `personIds`
///   y `priority` (gana la última no nula).
/// - Varios complete de la misma tarea: queda el último.
/// - Delete sobre un create pendiente: anula los dos y todas las ops de ese temporal.
/// - Delete de una tarea remota: quita sus update y complete previos.
/// - Delete de una lista: quita todas las ops de sus tareas; si la lista es local, anula su create.
public enum OutboxCompactor {
    /// Cola resultante tras encolar `op`. `idMap` traduce temporales ya resueltos, para reconocer el
    /// mismo recurso aunque una op lo nombre por su ID temporal y otra por el real.
    public static func enqueue(_ op: PendingOp, into ops: [PendingOp], inFlight: UUID?, idMap: [Int: Int] = [:]) -> [PendingOp] {
        var queue = ops
        let same: (Ref, Ref) -> Bool = { $0.normalized(with: idMap) == $1.normalized(with: idMap) }
        let mutable: (PendingOp) -> Bool = { $0.id != inFlight }
        // ¿Queda en la cola (aunque esté en vuelo) el create del temporal, o ya tiene ID real?
        let exists: (Ref) -> Bool = { ref in
            guard case .local(let id) = ref else { return true }
            return idMap[id] != nil || queue.contains { $0.kind.createdLocal == ref }
        }

        switch op.kind {
        case .createTask, .createList:
            queue.append(op)

        case .updateTask(let ref, let listRef, let title, let personIds, let priority):
            if let index = queue.firstIndex(where: { mutable($0) && $0.kind.createdLocal.map { same($0, ref) } == true }),
               case .createTask(let local, let createListRef, _, let createPersons, let createPriority) = queue[index].kind {
                queue[index].kind = .createTask(local: local, listRef: createListRef, title: title,
                                                personIds: personIds ?? createPersons, priority: priority ?? createPriority)
                return queue
            }
            var merged = op
            if let index = queue.lastIndex(where: { other in
                guard mutable(other), case .updateTask(let otherRef, _, _, _, _) = other.kind else { return false }
                return same(otherRef, ref)
            }), case .updateTask(_, _, _, let previousPersons, let previousPriority) = queue[index].kind {
                queue.remove(at: index)
                merged.kind = .updateTask(ref: ref, listRef: listRef, title: title,
                                          personIds: personIds ?? previousPersons, priority: priority ?? previousPriority)
            }
            queue.append(merged)

        case .completeTask(let ref, _, _):
            queue.removeAll { other in
                guard mutable(other), case .completeTask(let otherRef, _, _) = other.kind else { return false }
                return same(otherRef, ref)
            }
            queue.append(op)

        case .deleteTask(let ref, _):
            let hadPendingCreate = queue.contains { mutable($0) && $0.kind.createdLocal.map { same($0, ref) } == true }
            let resourceExists = exists(ref)
            queue.removeAll { other in mutable(other) && other.kind.taskRef.map { same($0, ref) } == true }
            if !hadPendingCreate && resourceExists { queue.append(op) }

        case .deleteList(let ref):
            let hadPendingCreate = queue.contains { mutable($0) && $0.kind.createdLocal.map { same($0, ref) } == true }
            let resourceExists = exists(ref)
            queue.removeAll { other in mutable(other) && same(other.kind.listRef, ref) }
            if !hadPendingCreate && resourceExists { queue.append(op) }

        case .updateList(let ref, let name, let color, let sort, let widget, let dashboard):
            if let index = queue.firstIndex(where: { mutable($0) && $0.kind.createdLocal.map { same($0, ref) } == true }),
               case .createList(let local, _, _, _, _, _) = queue[index].kind {
                queue[index].kind = .createList(local: local, name: name, color: color, sort: sort, widget: widget, dashboard: dashboard)
                return queue
            }
            queue.removeAll { other in
                guard mutable(other), case .updateList(let otherRef, _, _, _, _, _) = other.kind else { return false }
                return same(otherRef, ref)
            }
            queue.append(op)
        }
        return queue
    }
}
