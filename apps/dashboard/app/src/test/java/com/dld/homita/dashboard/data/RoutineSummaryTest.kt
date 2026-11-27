package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/** Rutinas diarias del calendario (U5): se resumen en una línea por día. */
class RoutineSummaryTest {
    private fun session(day: Int, hour: String, title: String) =
        Event(id = day, calendar_id = 1, calendar_name = "Casa", calendar_color = "#000000", title = title, date_at = "2026-12-%02d %s:00".format(day, hour), routine_id = 1)

    private val week = (1..7).map { session(it, "08:00", "Pastillas") } +
        listOf(session(2, "20:00", "Yoga"), session(4, "20:00", "Yoga"), session(6, "20:00", "Yoga")) +
        session(3, "09:00", "Fisio")

    @Test
    fun `una rutina que se repite casi a diario es diaria, una de tres dias no`() {
        val daily = RoutineSummary.dailyKeys(week)
        assertEquals(setOf("Pastillas|08:00"), daily)
    }

    @Test
    fun `cada dia separa las no diarias y cuenta las diarias`() {
        val daily = RoutineSummary.dailyKeys(week)
        val (others, dailyCount) = RoutineSummary.split(LocalDate.of(2026, 12, 2), week, daily)
        assertEquals(1, dailyCount)
        assertEquals(listOf("Yoga"), others.map { it.title })
        val (none, zero) = RoutineSummary.split(LocalDate.of(2026, 12, 3), week, daily)
        assertEquals(listOf("Fisio"), none.map { it.title })
        assertEquals(1, zero)
    }
}
