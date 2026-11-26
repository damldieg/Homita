package com.dld.homita.dashboard.data

import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

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

    /** Ventana del aviso (N2): solo lo que vence en menos de 48 h o ya ha vencido (N1: vencido hasta completarse). */
    const val WINDOW_HOURS = 48L

    /** Clave de un cierre del aviso: la tarea y su fecha, así un cambio de fecha vuelve a avisar (N4). */
    fun key(task: Task): String = "${task.id}@${task.due_at.orEmpty()}"

    /**
     * Tarea que destaca el banner de Hoy: la de prioridad alta, pendiente, con fecha que vence en menos de 48 h o ya
     * vencida, y no cerrada ([dismissed], claves de [key]). Entre varias, la que vence antes (las vencidas primero).
     */
    fun banner(
        tasks: List<Task>,
        now: LocalDateTime,
        dismissed: Set<String>,
        zone: ZoneId = ZoneId.systemDefault(),
    ): DueBanner? = tasks
        .asSequence()
        .filter { it.completed_at == null && it.priorityValue == TaskPriority.ALTA && key(it) !in dismissed }
        .mapNotNull { task ->
            local(task.due_at, zone)
                ?.takeIf { it.isBefore(now.plusHours(WINDOW_HOURS)) }
                ?.let { DueBanner(task, it, key(task)) }
        }
        .minByOrNull { it.due }

    /**
     * Cuándo vence, en el aviso: «Vencida hace 2 h» si ya pasó; «Hoy 19:00», «Mañana 19:00» o «vie 4 dic 19:00».
     * Con menos de un minuto de retraso, «Vencida ahora».
     */
    fun whenText(due: LocalDateTime, now: LocalDateTime): String {
        if (due.isBefore(now)) {
            val minutes = Duration.between(due, now).toMinutes()
            return when {
                minutes < 1 -> "Vencida ahora"
                minutes < 60 -> "Vencida hace $minutes min"
                minutes < 24 * 60 -> "Vencida hace ${minutes / 60} h"
                else -> "Vencida hace ${minutes / (24 * 60)} d"
            }
        }
        val hour = due.format(HOUR_FORMAT)
        return when (due.toLocalDate()) {
            now.toLocalDate() -> "Hoy $hour"
            now.toLocalDate().plusDays(1) -> "Mañana $hour"
            else -> due.format(DAY_FORMAT) + " " + hour
        }
    }

    private val HOUR_FORMAT = DateTimeFormatter.ofPattern("HH:mm")
    private val DAY_FORMAT = DateTimeFormatter.ofPattern("EEE d MMM", Locale.forLanguageTag("es-ES"))

    /** Banner de Hoy: [task] vence a [due] (hora local); [key] es su clave de cierre. */
    data class DueBanner(val task: Task, val due: LocalDateTime, val key: String)
}
