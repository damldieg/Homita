package com.dld.homita.dashboard.data

import java.time.LocalDateTime

/** Eventos de Hoy repartidos por fase (D-020): los «en curso» salen de los próximos. */
data class EventPartition(val ongoing: List<Event>, val upcoming: List<Event>)

/**
 * Separa [events] respecto a [now] (hora de referencia del marco). «En curso» = evento de varios días cuyo rango
 * contiene hoy. Próximos: el resto de hoy en adelante, sin [next] (ya está en su tarjeta). No guarda nada en disco:
 * se recalcula al pintar, así una caché viva cambia de sección tras medianoche sin red.
 */
fun partitionEvents(events: List<Event>, now: LocalDateTime, next: Event? = null): EventPartition {
    val today = now.toLocalDate()
    val ongoing = events.filter { it.isOngoing(today) }.sortedBy { it.at }
    val upcoming = events.filter { !it.isOngoing(today) && it.at.toLocalDate() >= today && it !== next }
    return EventPartition(ongoing, upcoming)
}
