package com.dld.homita.dashboard.data

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** Semana del menú (`GET /meal/plan?week_start=`, 0043-0048): solo lo que la pantalla muestra. */
data class MealPlanWeekResponse(
    val week_start: String? = null,
    val status: String? = null,
    val items: List<MealPlanWeekItem>? = null
)

data class MealPlanWeekItem(
    val day: String,
    val slot: String,
    val position: Int = 0,
    val kind: String? = null,
    val title: String? = null
)

/** Rejilla de la semana: días × franjas. Sin estado de pantalla: lo que se ve es lo que hay en el servidor. */
object MealWeekGrid {
    /** Franjas en el orden del día, como MealSlotKind.order de iOS. */
    val SLOT_ORDER = listOf("breakfast", "midmorning", "lunch", "snack", "dinner")

    private val ISO = DateTimeFormatter.ISO_LOCAL_DATE

    /** Lunes de la semana de [date]. */
    fun mondayOf(date: LocalDate): LocalDate = date.with(DayOfWeek.MONDAY)

    /** Los siete días de la semana que empieza en [monday], en orden. */
    fun days(monday: LocalDate): List<LocalDate> = (0L..6L).map { monday.plusDays(it) }

    /** Franjas que tienen algo en la semana, en el orden del día. */
    fun slots(items: List<MealPlanWeekItem>): List<String> {
        val present = items.map { it.slot }.toSet()
        return SLOT_ORDER.filter { it in present } + present.filterNot { it in SLOT_ORDER }.sorted()
    }

    /** Lo que va en una casilla (varios platos separados por «·»), o null si está vacía. */
    fun cell(items: List<MealPlanWeekItem>, day: LocalDate, slot: String): String? =
        items.filter { it.day == day.format(ISO) && it.slot == slot }
            .sortedBy { it.position }
            .mapNotNull { it.title?.trim()?.takeIf { t -> t.isNotEmpty() } }
            .takeIf { it.isNotEmpty() }
            ?.joinToString(" · ")
}
