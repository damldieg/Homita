package com.lito.planify.util

import com.lito.planify.data.api.EventResponse
import org.junit.Assert.*
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale

class AlarmQueueTest {
    private fun event(id: Int, date: String, alarm: Int? = 0) =
        EventResponse(id, 1, null, null, "Training", date, alarm, "", "")

    @Test fun limitsPendingAlarmsAndRefillsFromTheRemainingCache() {
        val events = (1..600).map { event(it, "2099-01-01 12:00:00") }
        val first = AlarmHelper.upcomingAlarms(events, 0)
        assertEquals(450, first.size)
        assertEquals(450, first.last().id)
        val refilled = AlarmHelper.upcomingAlarms(events.filterNot { it.id == first.first().id }, 0)
        assertEquals(450, refilled.size)
        assertEquals(451, refilled.last().id)
    }

    @Test fun prioritizesNotificationTimeAndSkipsMutedExpiredOrInvalidEvents() {
        val now = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).parse("2099-01-01 12:00:00")!!.time
        val events = listOf(
            event(1, "2099-01-01 13:00:00"),
            event(2, "2099-01-01 14:00:00", 90),
            event(3, "2099-01-01 13:00:00", null),
            event(4, "2099-01-01 13:00:00", 120),
            event(5, "invalid"),
            event(6, "2099-01-01 13:00:00", Int.MAX_VALUE)
        )
        assertEquals(listOf(2, 1), AlarmHelper.upcomingAlarms(events, now).map { it.id })
    }
}
