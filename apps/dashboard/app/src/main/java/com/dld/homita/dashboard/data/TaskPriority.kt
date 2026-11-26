package com.dld.homita.dashboard.data

/**
 * Prioridad de una tarea (migración 0037, D-026). [raw] es el valor de la API (`alta`/`media`/`baja`) y [rank]
 * el orden: alta (1) > media (2) > baja (3).
 */
enum class TaskPriority(val raw: String, val rank: Int, val label: String) {
    ALTA("alta", 1, "Alta"),
    MEDIA("media", 2, "Media"),
    BAJA("baja", 3, "Baja");

    companion object {
        /** Valor de la API; ausente (caché antigua, API sin 0037) o desconocido → [MEDIA], el default del servidor. */
        fun from(raw: String?): TaskPriority = entries.firstOrNull { it.raw == raw } ?: MEDIA
    }
}

/** Prioridad efectiva de la tarea (ver [TaskPriority.from]). */
val Task.priorityValue: TaskPriority get() = TaskPriority.from(priority)

/**
 * Orden fijo por prioridad dentro de cada lista (dashboard-hoy-legible, C5): pendientes antes que completadas, después
 * alta > media > baja y, a igual prioridad, el orden de la lista (`order`) y el id, como el servidor. `sortedWith` es
 * estable. Lógica pura para poder probarla sin Android.
 */
object TaskPriorityView {
    fun sortWithinList(tasks: List<Task>): List<Task> =
        tasks.sortedWith(compareBy<Task>({ it.completed_at != null }, { it.priorityValue.rank }, { it.order }, { it.id }))
}
