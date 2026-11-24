package com.dld.homita.dashboard.data

import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Una fila de la tarjeta «Hoy se come». [past]: la franja ya pasó; [current]: la franja actual o la siguiente. */
data class MealRow(val time: String, val label: String, val title: String, val past: Boolean, val current: Boolean)

/** Lo que enseña la tarjeta: las filas visibles y cuántas casillas quedan fuera ([more], el «+N»). */
data class MealsTodayView(val rows: List<MealRow>, val more: Int)

/**
 * Lógica pura de la tarjeta de menú. La hora y el día son los del hogar (`timezone` de la respuesta) a partir del
 * reloj del dispositivo, no `now_local` (que envejece con la copia). La franja actual es la primera casilla con
 * `time >= ahora` (al minuto, como iOS); las anteriores se atenúan. Se enseñan como mucho [MAX_ROWS] filas, desde la
 * actual; si ya han pasado todas, las últimas.
 */
object MealsTodayState {
    const val MAX_ROWS = 3

    /** null = ocultar la tarjeta: sin dato, de otro día, sin plan aceptado o sin casillas con título. */
    fun of(
        meals: MealsToday?,
        now: LocalDateTime,
        maxRows: Int = MAX_ROWS,
        deviceZone: ZoneId = ZoneId.systemDefault()
    ): MealsTodayView? {
        if (meals == null || !meals.has_plan) return null
        val home = runCatching { ZoneId.of(meals.timezone.orEmpty()) }.getOrDefault(deviceZone)
        val homeNow = now.atZone(deviceZone).withZoneSameInstant(home).toLocalDateTime().truncatedTo(ChronoUnit.MINUTES)
        if (meals.date != homeNow.toLocalDate().toString()) return null
        val nowTime = homeNow.toLocalTime()
        val items = meals.items.orEmpty()
            .filter { !it.title.isNullOrBlank() && !it.time.isNullOrBlank() && parse(it.time) != null }
            .sortedBy { parse(it.time) }
        if (items.isEmpty()) return null
        val currentIndex = items.indexOfFirst { parse(it.time)!! >= nowTime }
        val start = if (currentIndex >= 0) currentIndex else (items.size - maxRows).coerceAtLeast(0)
        val rows = items.drop(start).take(maxRows).map { item ->
            MealRow(
                time = item.time.orEmpty(),
                label = slotLabel(item.slot),
                title = item.title.orEmpty().trim(),
                past = parse(item.time)!! < nowTime,
                current = currentIndex >= 0 && item === items[currentIndex]
            )
        }
        return MealsTodayView(rows, items.size - rows.size)
    }

    private fun parse(time: String?): LocalTime? = runCatching { LocalTime.parse(time.orEmpty()) }.getOrNull()

    fun slotLabel(slot: String?): String = when (slot) {
        "breakfast" -> "Desayuno"
        "midmorning" -> "Media mañana"
        "lunch" -> "Comida"
        "snack" -> "Merienda"
        "dinner" -> "Cena"
        else -> ""
    }
}
