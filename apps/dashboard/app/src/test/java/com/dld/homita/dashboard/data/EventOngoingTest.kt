package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

/** D-020: clasificación «en curso» por día, sin hora (CA-10, CA-11). */
class EventOngoingTest {
    private fun event(id: Int = 1, dateAt: String = "2026-11-10 09:00:00", end: String? = "2026-11-20") =
        Event(id, 1, "Casa", "#000000", "Vacaciones", dateAt, end_date = end)

    private fun day(d: Int) = LocalDate.of(2026, 11, d)

    @Test
    fun boundariesAreInclusive() {
        val e = event()
        assertFalse(e.isOngoing(day(9)))
        assertTrue(e.isOngoing(day(10)))
        assertTrue(e.isOngoing(day(15)))
        assertTrue(e.isOngoing(day(20)))
        assertFalse(e.isOngoing(day(21)))
    }

    @Test
    fun withoutOrMalformedEndIsNeverOngoing() {
        assertFalse(event(end = null).isOngoing(day(10)))
        for (bad in listOf("", "abc", "2026-13-40", "20/11")) assertFalse(bad, event(end = bad).isOngoing(day(15)))
        assertEquals(null, event(end = "abc").endDay)
    }

    @Test
    fun partitionMovesOngoingOutOfUpcoming() {
        val vacation = event(1)
        val single = event(2, "2026-11-16 10:00:00", null)
        val now = LocalDateTime.of(2026, 11, 15, 12, 0)
        val parts = partitionEvents(listOf(vacation, single), now, next = null)
        assertEquals(listOf(vacation), parts.ongoing)
        assertEquals(listOf(single), parts.upcoming)
    }

    @Test
    fun partitionWithoutEndsKeepsTheOldFilter() {
        val past = event(1, "2026-11-14 10:00:00", null)
        val today = event(2, "2026-11-15 08:00:00", null)
        val next = event(3, "2026-11-15 18:00:00", null)
        val later = event(4, "2026-11-18 10:00:00", null)
        val now = LocalDateTime.of(2026, 11, 15, 12, 0)
        val parts = partitionEvents(listOf(past, today, next, later), now, next)
        assertTrue(parts.ongoing.isEmpty())
        assertEquals(listOf(today, later), parts.upcoming)
    }

    @Test
    fun partitionWithBoundaryDays() {
        val vacation = event()
        assertEquals(1, partitionEvents(listOf(vacation), LocalDateTime.of(2026, 11, 10, 0, 1)).ongoing.size)
        assertEquals(1, partitionEvents(listOf(vacation), LocalDateTime.of(2026, 11, 20, 23, 59)).ongoing.size)
        val before = partitionEvents(listOf(vacation), LocalDateTime.of(2026, 11, 9, 12, 0))
        assertTrue(before.ongoing.isEmpty())
        assertEquals(1, before.upcoming.size)
        val after = partitionEvents(listOf(vacation), LocalDateTime.of(2026, 11, 21, 0, 0))
        assertTrue(after.ongoing.isEmpty() && after.upcoming.isEmpty())
    }

    @Test
    fun endEqualToStartDayIsASingleDayEvent() {
        val e = event(end = "2026-11-10")
        assertEquals(null, e.endDay)
        assertFalse(e.isOngoing(day(10)))
        val now = LocalDateTime.of(2026, 11, 10, 8, 0)
        val parts = partitionEvents(listOf(e), now, next = null)
        assertTrue(parts.ongoing.isEmpty())
        assertEquals(listOf(e), parts.upcoming)
        // Un fin anterior al inicio tampoco es un rango.
        assertEquals(null, event(end = "2026-11-09").endDay)
        // Fin un día después: sí es rango.
        assertTrue(event(end = "2026-11-11").isOngoing(day(11)))
    }
}
