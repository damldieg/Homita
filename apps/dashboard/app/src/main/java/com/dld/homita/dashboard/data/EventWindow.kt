package com.dld.homita.dashboard.data

import java.time.LocalDate

/** Días después de hoy que entran en «Próximas dos semanas»: de mañana a hoy+13 (hoy+14 queda fuera). */
const val UPCOMING_WINDOW_DAYS = 13L

/**
 * Eventos de la ventana de dos semanas: de mañana a hoy+[UPCOMING_WINDOW_DAYS] inclusive, sin los «en curso»
 * (los de hoy los cubre Hoy), ordenados por inicio.
 */
fun upcomingWindowEvents(events: List<Event>, today: LocalDate): List<Event> {
    val from = today.plusDays(1)
    val to = today.plusDays(UPCOMING_WINDOW_DAYS)
    return events.filter { !it.isOngoing(today) && it.at.toLocalDate() in from..to }.sortedBy { it.at }
}
