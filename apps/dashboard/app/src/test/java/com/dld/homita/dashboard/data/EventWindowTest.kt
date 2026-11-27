package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

/** Ventana «Próximas dos semanas»: mañana..hoy+13, sin hoy ni en curso. */
class EventWindowTest {
    private val sql = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

    private fun event(id: Int, at: LocalDateTime, end: String? = null) =
        Event(id, 1, "Casa", "#000000", "E$id", at.format(sql), end_date = end)

    private val today = LocalDate.of(2026, 11, 10)
    private fun at(offset: Long) = today.plusDays(offset).atTime(9, 0)
    private fun ids(events: List<Event>, day: LocalDate = today) = upcomingWindowEvents(events, day).map { it.id }

    @Test
    fun includesTomorrowAndDay13ExcludesDay14() {
        assertEquals(listOf(1, 2), ids(listOf(event(3, at(14)), event(2, at(13)), event(1, at(1)))))
    }

    @Test
    fun excludesToday() {
        assertEquals(emptyList<Int>(), ids(listOf(event(1, at(0)))))
    }

    @Test
    fun excludesMultiDayEventStartedYesterdayAndStillOngoing() {
        val e = event(1, at(-1), end = "2026-11-12")
        assertEquals(emptyList<Int>(), ids(listOf(e)))
    }

    @Test
    fun dayChangeMovesEventInAndOut() {
        val e = event(1, at(14))
        assertEquals(emptyList<Int>(), ids(listOf(e)))
        assertEquals(listOf(1), ids(listOf(e), today.plusDays(1)))
        assertEquals(emptyList<Int>(), ids(listOf(e), today.plusDays(14)))
    }
}
