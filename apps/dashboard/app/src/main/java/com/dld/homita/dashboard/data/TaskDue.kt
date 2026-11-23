package com.dld.homita.dashboard.data

import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Fecha límite de una tarea (0041, fecha-limite-vencimiento). La API la da en UTC (`yyyy-MM-dd HH:mm:ss`) y aquí
 * se muestra en la hora local del dispositivo. Lógica pura para poder probarla sin Android.
 */
object TaskDue {
    private val API_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val LABEL_FORMAT = DateTimeFormatter.ofPattern("dd/MM HH:mm")

    /** Fecha límite en [zone]; null si no hay fecha o no se puede leer (una fecha ilegible no rompe la fila). */
    fun local(raw: String?, zone: ZoneId = ZoneId.systemDefault()): LocalDateTime? = runCatching {
        LocalDateTime.parse(raw, API_FORMAT).atOffset(ZoneOffset.UTC).atZoneSameInstant(zone).toLocalDateTime()
    }.getOrNull()

    /** Texto corto para la fila: «03/12 19:00», en la hora local. Null si no hay fecha válida. */
    fun label(raw: String?, zone: ZoneId = ZoneId.systemDefault()): String? =
        local(raw, zone)?.format(LABEL_FORMAT)

    /**
     * Tarea que destaca el banner de Hoy: la de prioridad alta, pendiente y con fecha futura que vence antes,
     * salvo las cerradas en esta sesión ([dismissed]). Null si no hay ninguna.
     */
    fun banner(
        tasks: List<Task>,
        now: LocalDateTime,
        dismissed: Set<Int>,
        zone: ZoneId = ZoneId.systemDefault(),
    ): DueBanner? = tasks
        .asSequence()
        .filter { it.completed_at == null && it.priorityValue == TaskPriority.ALTA && it.id !in dismissed }
        .mapNotNull { task -> local(task.due_at, zone)?.takeIf { it.isAfter(now) }?.let { DueBanner(task, it) } }
        .minByOrNull { it.due }

    /** Banner de Hoy: [task] vence a [due] (hora local). */
    data class DueBanner(val task: Task, val due: LocalDateTime)
}
