package com.dld.homita.dashboard.data

import java.time.LocalDate

/** Una fila de la tarjeta «Hoy se come». [past]: la franja ya pasó; [current]: la franja actual o la siguiente. */
data class MealRow(val time: String, val label: String, val title: String, val past: Boolean, val current: Boolean)

/** Lo que enseña la tarjeta: las filas visibles y cuántas casillas quedan fuera ([more], el «+N»). */
data class MealsTodayView(val rows: List<MealRow>, val more: Int)

/**
 * Lógica pura de la tarjeta de menú. La franja actual es la primera casilla con `time >= now_local`, con la hora
 * del servidor (no la del dispositivo); las anteriores se atenúan. Se enseñan como mucho [MAX_ROWS] filas, desde la
 * actual; si ya han pasado todas, las últimas.
 */
object MealsTodayState {
    const val MAX_ROWS = 3

    /** null = ocultar la tarjeta: sin dato, de otro día, sin plan aceptado o sin casillas con título. */
    fun of(meals: MealsToday?, today: LocalDate, maxRows: Int = MAX_ROWS): MealsTodayView? {
        if (meals == null || !meals.has_plan || meals.date != today.toString()) return null
        val items = meals.items.orEmpty()
            .filter { !it.title.isNullOrBlank() && !it.time.isNullOrBlank() }
            .sortedBy { it.time }
        if (items.isEmpty()) return null
        val nowLocal = meals.now_local.orEmpty()
        val currentIndex = items.indexOfFirst { it.time.orEmpty() >= nowLocal }
        val start = if (currentIndex >= 0) currentIndex else (items.size - maxRows).coerceAtLeast(0)
        val rows = items.drop(start).take(maxRows).map { item ->
            MealRow(
                time = item.time.orEmpty(),
                label = slotLabel(item.slot),
                title = item.title.orEmpty().trim(),
                past = item.time.orEmpty() < nowLocal,
                current = currentIndex >= 0 && item === items[currentIndex]
            )
        }
        return MealsTodayView(rows, items.size - rows.size)
    }

    fun slotLabel(slot: String?): String = when (slot) {
        "breakfast" -> "Desayuno"
        "midmorning" -> "Media mañana"
        "lunch" -> "Comida"
        "snack" -> "Merienda"
        "dinner" -> "Cena"
        else -> ""
    }
}
