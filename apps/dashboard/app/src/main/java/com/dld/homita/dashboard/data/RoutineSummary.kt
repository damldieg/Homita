package com.dld.homita.dashboard.data

import java.time.LocalDate

/**
 * Rutinas diarias del calendario (U5): las que se repiten todos los días de la semana se resumen en una línea
 * («+3 rutinas diarias») en vez de ocupar cada día. Lógica pura para poder probarla sin Android.
 */
object RoutineSummary {
    /** Una rutina es diaria si su título y hora aparecen en al menos esta cantidad de días de la semana. */
    const val DAILY_MIN_DAYS = 6

    /** Claves («título|HH:mm») de las rutinas que se repiten a diario en [weekSessions]. */
    fun dailyKeys(weekSessions: List<Event>): Set<String> =
        weekSessions
            .groupBy { key(it) }
            .filterValues { sessions -> sessions.map { it.at.toLocalDate() }.distinct().size >= DAILY_MIN_DAYS }
            .keys

    /** Las sesiones de [day] que no son diarias, y cuántas diarias hay ese día. */
    fun split(day: LocalDate, sessions: List<Event>, dailyKeys: Set<String>): Pair<List<Event>, Int> {
        val mine = sessions.filter { it.at.toLocalDate() == day }
        val daily = mine.count { key(it) in dailyKeys }
        return mine.filter { key(it) !in dailyKeys } to daily
    }

    private fun key(event: Event) = "${event.title}|${event.at.toLocalTime().withSecond(0).withNano(0)}"
}
