package com.dld.homita.dashboard.data.repository

import com.dld.homita.dashboard.data.Api
import com.dld.homita.dashboard.data.CompleteTaskRequest
import com.dld.homita.dashboard.data.AuthRequest
import com.dld.homita.dashboard.data.Event
import com.dld.homita.dashboard.data.Forecast
import com.dld.homita.dashboard.data.GeoResponse
import com.dld.homita.dashboard.data.MealsToday
import com.dld.homita.dashboard.data.MealPlanWeekResponse
import com.dld.homita.dashboard.data.MealProfileSafe
import com.dld.homita.dashboard.data.ShoppingCheckRequest
import com.dld.homita.dashboard.data.ShoppingListResponse
import com.dld.homita.dashboard.data.ShoppingWebItem
import com.dld.homita.dashboard.data.RefreshRequest
import com.dld.homita.dashboard.data.SessionResponse
import com.dld.homita.dashboard.data.Task
import com.dld.homita.dashboard.data.UserResponse
import com.dld.homita.dashboard.data.cache.DiskCache
import com.dld.homita.dashboard.data.isUnauthorized
import kotlinx.coroutines.runBlocking
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import retrofit2.Response
import java.io.IOException
import java.time.LocalDate

class CalendarRepositoryTest {
    @get:Rule
    val folder = TemporaryFolder()

    /** API falsa: devuelve un evento por petición, o falla como se le diga. */
    private class FakeApi : Api {
        var failure: Exception? = null
        var status = 200
        var endDate: String? = null

        override suspend fun events(auth: String, start: Long, end: Long?, routine: Boolean, timezone: String, dashboard: Boolean): Response<List<Event>> {
            failure?.let { throw it }
            if (status != 200) return Response.error(status, "".toResponseBody())
            return Response.success(listOf(Event(1, 1, "Casa", "#000000", if (routine) "Rutina" else "Evento", "2026-10-14 10:00:00", end_date = endDate)))
        }

        override suspend fun auth(request: AuthRequest): Response<UserResponse> = error("no se usa")
        override suspend fun refresh(request: RefreshRequest): Response<SessionResponse> = error("no se usa")
        override suspend fun completeTask(auth: String, request: CompleteTaskRequest): Response<Task> = error("no se usa")
        override suspend fun tasks(auth: String, dashboard: Boolean): Response<List<Task>> = error("no se usa")
        override suspend fun mealProfile(auth: String): Response<MealProfileSafe> = error("no se usa")
        override suspend fun checkShoppingItem(auth: String, request: ShoppingCheckRequest): Response<ShoppingWebItem> = error("no se usa")
        override suspend fun shopping(auth: String): Response<ShoppingListResponse> = error("no se usa")
        override suspend fun mealPlan(auth: String, weekStart: String): Response<MealPlanWeekResponse> = error("no se usa")
        override suspend fun mealsToday(auth: String): Response<MealsToday> = error("no se usa")
        override suspend fun forecast(url: String): Response<Forecast> = error("no se usa")
        override suspend fun geocode(url: String): Response<GeoResponse> = error("no se usa")
    }

    private val api = FakeApi()
    private var clock = 1_000_000L
    private val monday = LocalDate.of(2026, 10, 12)

    private fun repository() = CalendarRepository(api, DiskCache(folder.root), now = { clock })

    @Test
    fun downloadedWeekIsAvailableAfterRestart() = runBlocking {
        repository().refresh("token", monday)
        val week = repository().weeks.value[monday]
        assertEquals("Evento", week?.events?.single()?.title)
        assertEquals("Rutina", week?.sessions?.single()?.title)
    }

    @Test
    fun offlineKeepsTheCachedWeek() = runBlocking {
        val repository = repository()
        repository.refresh("token", monday)
        clock += CalendarRepository.MAX_AGE_MS
        assertTrue(repository.isStale(monday))
        api.failure = IOException("sin red")
        assertTrue(repository.refresh("token", monday).isFailure)
        assertEquals(1, repository.weeks.value[monday]?.events?.size)
    }

    @Test
    fun expiredSessionIsReportedAsUnauthorized() = runBlocking {
        api.status = 401
        val error = repository().refresh("token", monday).exceptionOrNull()
        assertTrue(error?.isUnauthorized == true)
    }

    @Test
    fun keepsOnlyTheMostRecentlyDownloadedWeeks() = runBlocking {
        val repository = repository()
        val mondays = (0L until CalendarRepository.KEEP + 3L).map { monday.plusWeeks(it) }
        mondays.forEach {
            clock += 1_000
            repository.refresh("token", it)
        }
        val kept = mondays.takeLast(CalendarRepository.KEEP).toSet()
        assertEquals(kept, repository.weeks.value.keys)
        assertEquals(kept, repository().weeks.value.keys)
    }

    @Test
    fun clearForgetsEverything() = runBlocking {
        val repository = repository()
        repository.refresh("token", monday)
        repository.clear()
        assertTrue(repository.weeks.value.isEmpty())
        assertTrue(repository().weeks.value.isEmpty())
    }

    @Test
    fun endDateTravelsThroughTheCacheAndOffline() = runBlocking {
        api.endDate = "2026-10-20"
        val repository = repository()
        repository.refresh("token", monday)
        clock += CalendarRepository.MAX_AGE_MS
        api.failure = IOException("sin red")
        assertTrue(repository.refresh("token", monday).isFailure)
        assertEquals("2026-10-20", repository().weeks.value[monday]?.events?.single()?.end_date)
    }

    @Test
    fun cacheWrittenBeforeEndDateLoadsWithNull() {
        // Fichero de una versión anterior: sin la clave `end_date`.
        val old = """{"value":{"events":[{"id":1,"calendar_id":1,"calendar_name":"Casa","calendar_color":"#000000",""" +
            """"title":"Evento","date_at":"2026-10-14 10:00:00"}],"sessions":[]},"fetchedAt":$clock}"""
        folder.root.mkdirs()
        java.io.File(folder.root, "week-$monday.json").writeText(old)
        val event = repository().weeks.value[monday]?.events?.single()
        assertEquals("Evento", event?.title)
        assertEquals(null, event?.end_date)
        assertTrue(event?.isOngoing(monday) == false)
    }

    @Test
    fun multiDayEventKeepsItsStartDateAtAndIsNotOngoingOutsideItsRange() {
        // Cobertura acotada: el filtro por día de CalendarScreen (`it.at.toLocalDate() == date`) es
        // inline en un composable y no se puede ejercitar sin UI. Aquí solo se verifica el dato que
        // ese filtro usa: `at` sigue siendo el día de inicio (DD-12), y `isOngoing` no se confunde
        // con él. NO se prueba el pintado de la semana.
        val vacation = Event(9, 1, "Casa", "#000000", "Vacaciones", "2026-11-10 09:00:00", end_date = "2026-11-20")
        assertEquals(LocalDate.of(2026, 11, 10), vacation.at.toLocalDate())
        assertTrue(vacation.isOngoing(LocalDate.of(2026, 11, 16)))
        assertTrue(vacation.at.toLocalDate() != LocalDate.of(2026, 11, 16))
    }
}
