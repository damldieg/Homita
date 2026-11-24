package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class MealsTodayStateTest {
    private val today = LocalDate.of(2026, 11, 24)

    private fun item(id: Int, slot: String, time: String, title: String?) = MealItem(id, slot, time, "free", title)

    private val all = listOf(
        item(1, "breakfast", "08:00", "Tostada"),
        item(2, "lunch", "14:00", "Lentejas"),
        item(3, "snack", "17:30", "Fruta"),
        item(4, "dinner", "21:00", "Tortilla")
    )

    private fun menu(now: String, items: List<MealItem> = all, date: String = "2026-11-24", plan: Boolean = true) =
        MealsToday(has_plan = plan, date = date, timezone = "Europe/Madrid", now_local = now, items = items)

    @Test
    fun currentSlotIsTheFirstNotPassed() {
        val view = MealsTodayState.of(menu("12:00"), today)!!
        assertEquals(listOf("14:00", "17:30", "21:00"), view.rows.map { it.time })
        assertTrue(view.rows[0].current)
        assertFalse(view.rows[1].current)
        assertTrue(view.rows.none { it.past })
        assertEquals(1, view.more)
    }

    @Test
    fun sameMinuteCountsAsCurrent() {
        val view = MealsTodayState.of(menu("14:00"), today)!!
        assertEquals("14:00", view.rows.first().time)
        assertTrue(view.rows.first().current)
        assertFalse(view.rows.first().past)
    }

    @Test
    fun allPassedShowsTheLastOnesDimmed() {
        val view = MealsTodayState.of(menu("22:30"), today)!!
        assertEquals(listOf("14:00", "17:30", "21:00"), view.rows.map { it.time })
        assertTrue(view.rows.all { it.past && !it.current })
        assertEquals(1, view.more)
    }

    @Test
    fun trimsToMaxRowsAndCountsTheRest() {
        val view = MealsTodayState.of(menu("06:00"), today, maxRows = 1)!!
        assertEquals(1, view.rows.size)
        assertEquals("Desayuno", view.rows.single().label)
        assertEquals(3, view.more)
    }

    @Test
    fun sortsByTimeAndSkipsBlankTitles() {
        val items = listOf(item(2, "dinner", "21:00", "Tortilla"), item(1, "lunch", "14:00", "Lentejas"), item(3, "snack", "17:30", "  "))
        val view = MealsTodayState.of(menu("00:00", items), today)!!
        assertEquals(listOf("Lentejas", "Tortilla"), view.rows.map { it.title })
        assertEquals(0, view.more)
    }

    @Test
    fun hiddenWithoutPlanItemsOrForOtherDay() {
        assertNull(MealsTodayState.of(null, today))
        assertNull(MealsTodayState.of(menu("12:00", plan = false), today))
        assertNull(MealsTodayState.of(menu("12:00", items = emptyList()), today))
        assertNull(MealsTodayState.of(menu("12:00", items = listOf(item(1, "lunch", "14:00", null))), today))
        assertNull(MealsTodayState.of(menu("12:00", date = "2026-11-23"), today))
    }

    @Test
    fun slotLabelsAreSpanish() {
        assertEquals("Media mañana", MealsTodayState.slotLabel("midmorning"))
        assertEquals("", MealsTodayState.slotLabel("otro"))
        assertEquals("", MealsTodayState.slotLabel(null))
    }
}
