package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class MealsTodayStateTest {
    private val madrid = ZoneId.of("Europe/Madrid")
    private val day = LocalDate.of(2026, 11, 24)

    private fun at(time: String, date: LocalDate = day) = LocalDateTime.of(date, java.time.LocalTime.parse(time))

    private fun of(meals: MealsToday?, now: LocalDateTime, maxRows: Int = MealsTodayState.MAX_ROWS, zone: ZoneId = madrid) =
        MealsTodayState.of(meals, now, maxRows, zone)

    private fun item(id: Int, slot: String, time: String, title: String?) = MealItem(id, slot, time, "free", title)

    private val all = listOf(
        item(1, "breakfast", "08:00", "Tostada"),
        item(2, "lunch", "14:00", "Lentejas"),
        item(3, "snack", "17:30", "Fruta"),
        item(4, "dinner", "21:00", "Tortilla")
    )

    private fun menu(now: String = "00:00", items: List<MealItem> = all, date: String = "2026-11-24", plan: Boolean = true) =
        MealsToday(has_plan = plan, date = date, timezone = "Europe/Madrid", now_local = now, items = items)

    @Test
    fun currentSlotIsTheFirstNotPassed() {
        val view = of(menu("12:00"), at("12:00"))!!
        assertEquals(listOf("14:00", "17:30"), view.rows.map { it.time })
        assertTrue(view.rows[0].current)
        assertFalse(view.rows[1].current)
        assertTrue(view.rows.none { it.past })
        assertEquals(2, view.more)
    }

    @Test
    fun sameMinuteCountsAsCurrent() {
        val view = of(menu("14:00"), at("14:00"))!!
        assertEquals("14:00", view.rows.first().time)
        assertTrue(view.rows.first().current)
        assertFalse(view.rows.first().past)
    }

    @Test
    fun allPassedShowsTheLastOnesDimmed() {
        val view = of(menu("22:30"), at("22:30"))!!
        assertEquals(listOf("17:30", "21:00"), view.rows.map { it.time })
        assertTrue(view.rows.all { it.past && !it.current })
        assertEquals(2, view.more)
        assertEquals(2, MealsTodayState.MAX_ROWS)
    }

    @Test
    fun trimsToMaxRowsAndCountsTheRest() {
        val view = of(menu("06:00"), at("06:00"), maxRows = 1)!!
        assertEquals(1, view.rows.size)
        assertEquals("Desayuno", view.rows.single().label)
        assertEquals(3, view.more)
    }

    @Test
    fun sortsByTimeAndSkipsBlankTitles() {
        val items = listOf(item(2, "dinner", "21:00", "Tortilla"), item(1, "lunch", "14:00", "Lentejas"), item(3, "snack", "17:30", "  "))
        val view = of(menu("00:00", items), at("00:00"))!!
        assertEquals(listOf("Lentejas", "Tortilla"), view.rows.map { it.title })
        assertEquals(0, view.more)
    }

    @Test
    fun hiddenWithoutPlanItemsOrForOtherDay() {
        assertNull(of(null, at("12:00")))
        assertNull(of(menu("12:00", plan = false), at("12:00")))
        assertNull(of(menu("12:00", items = emptyList()), at("12:00")))
        assertNull(of(menu("12:00", items = listOf(item(1, "lunch", "14:00", null))), at("12:00")))
        assertNull(of(menu("12:00", date = "2026-11-23"), at("12:00")))
    }

    @Test
    fun currentSlotUsesTheHomeZoneNotTheStaleServerClock() {
        // now_local de la copia dice 08:00, pero ya son las 15:00 del hogar: la actual es la de 17:30
        val view = of(menu("08:00"), at("15:00"))!!
        assertEquals("17:30", view.rows.first().time)
        assertTrue(view.rows.first().current)
    }

    @Test
    fun pastSlotsAreDimmedAsTimePasses() {
        val before = of(menu(), at("13:59"))!!
        assertEquals("14:00", before.rows.first().time)
        assertFalse(before.rows.first().past)
        // Un minuto después de las 14:00 la actual pasa a ser la de 17:30 (la de las 14:00 ya no se enseña)
        val after = of(menu(), at("14:01"))!!
        assertEquals("17:30", after.rows.first().time)
        assertTrue(after.rows.first().current)
        // Pasadas todas, se enseñan las últimas atenuadas
        assertTrue(of(menu(), at("21:01"))!!.rows.all { it.past })
    }

    @Test
    fun dayAndTimeFollowTheHomeZoneWhenTheDeviceDiffers() {
        // Dispositivo en UTC a las 23:30 del 23: en Madrid ya es 00:30 del 24 y el menú de hoy se ve
        val utc = ZoneId.of("UTC")
        val view = of(menu(), at("23:30", day.minusDays(1)), zone = utc)!!
        assertEquals("08:00", view.rows.first().time)
        assertTrue(view.rows.first().current)
        // Dispositivo en Madrid a las 23:30 del 24 con menú del 24 y hogar en Canarias (22:30): sigue siendo hoy
        val canarias = menu().copy(timezone = "Atlantic/Canary")
        assertEquals("21:00", of(canarias, at("20:30"), zone = madrid)!!.rows.first { it.current }.time)
        // Madrid 00:30 del 25 = Canarias 23:30 del 24: el menú del 24 sigue vigente
        assertTrue(of(canarias, at("00:30", day.plusDays(1)), zone = madrid) != null)
    }

    @Test
    fun slotLabelsAreSpanish() {
        assertEquals("Media mañana", MealsTodayState.slotLabel("midmorning"))
        assertEquals("", MealsTodayState.slotLabel("otro"))
        assertEquals("", MealsTodayState.slotLabel(null))
    }
}
