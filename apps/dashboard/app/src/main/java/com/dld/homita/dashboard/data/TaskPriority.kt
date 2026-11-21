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

/** Orden de la pantalla de tareas: [LIST] es el de siempre (el del servidor); [PRIORITY], alta > media > baja. */
enum class TaskSort(val label: String) {
    LIST("Lista"),
    PRIORITY("Prioridad");

    companion object {
        /** Valor guardado en [Store]; desconocido o ausente → [LIST]. */
        fun from(name: String?): TaskSort = entries.firstOrNull { it.name == name } ?: LIST
    }
}

/**
 * Orden y filtro por prioridad en cliente, sobre las tareas ya cacheadas (la caché y el stale-if-error no cambian).
 * Lógica pura para poder probarla sin Android.
 */
object TaskPriorityView {
    /** Solo las tareas de [filter]; null = todas. */
    fun filterTasks(tasks: List<Task>, filter: TaskPriority?): List<Task> =
        if (filter == null) tasks else tasks.filter { it.priorityValue == filter }

    /**
     * Con [TaskSort.LIST] la lista tal cual. Con [TaskSort.PRIORITY], pendientes antes que completadas, después el
     * rango y, a igual prioridad, el orden de la lista (`order`) y el id, como el servidor. `sortedWith` es estable.
     */
    fun sortTasks(tasks: List<Task>, sort: TaskSort): List<Task> = when (sort) {
        TaskSort.LIST -> tasks
        TaskSort.PRIORITY -> tasks.sortedWith(
            compareBy<Task>({ it.completed_at != null }, { it.priorityValue.rank }, { it.order }, { it.id })
        )
    }

    /** Filtro y después orden: lo que muestra la pantalla de tareas. */
    fun apply(tasks: List<Task>, sort: TaskSort, filter: TaskPriority?): List<Task> = sortTasks(filterTasks(tasks, filter), sort)
}
