package com.dld.homita.dashboard.data.repository

import com.dld.homita.dashboard.data.Api
import com.dld.homita.dashboard.data.CompleteTaskRequest
import com.dld.homita.dashboard.data.AuthRequest
import com.dld.homita.dashboard.data.Event
import com.dld.homita.dashboard.data.Forecast
import com.dld.homita.dashboard.data.GeoResponse
import com.dld.homita.dashboard.data.MealItem
import com.dld.homita.dashboard.data.MealsToday
import com.dld.homita.dashboard.data.MealPlanWeekResponse
import com.dld.homita.dashboard.data.MealProfileSafe
import com.dld.homita.dashboard.data.ShoppingListResponse
import com.dld.homita.dashboard.data.RefreshRequest
import com.dld.homita.dashboard.data.SessionResponse
import com.dld.homita.dashboard.data.Task
import com.dld.homita.dashboard.data.UserResponse
import com.dld.homita.dashboard.data.cache.DiskCache
import com.dld.homita.dashboard.data.isUnauthorized
import kotlinx.coroutines.runBlocking
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import retrofit2.Response
import java.io.IOException
import java.time.LocalDate

class MealRepositoryTest {
    @get:Rule
    val folder = TemporaryFolder()

    private class FakeApi : Api {
        var failure: Exception? = null
        var status = 200
        var meals = MealsToday(
            has_plan = true, date = "2026-11-24", timezone = "Europe/Madrid", now_local = "13:00",
            items = listOf(MealItem(1, "lunch", "14:00", "free", "Lentejas"))
        )
        var auth: String? = null

        override suspend fun mealProfile(auth: String): Response<MealProfileSafe> = error("no se usa")
        override suspend fun shopping(auth: String): Response<ShoppingListResponse> = error("no se usa")
        override suspend fun mealPlan(auth: String, weekStart: String): Response<MealPlanWeekResponse> = error("no se usa")
        override suspend fun mealsToday(auth: String): Response<MealsToday> {
            this.auth = auth
            failure?.let { throw it }
            if (status != 200) return Response.error(status, "".toResponseBody())
            return Response.success(meals)
        }

        override suspend fun auth(request: AuthRequest): Response<UserResponse> = error("no se usa")
        override suspend fun refresh(request: RefreshRequest): Response<SessionResponse> = error("no se usa")
        override suspend fun completeTask(auth: String, request: CompleteTaskRequest): Response<Task> = error("no se usa")
        override suspend fun events(auth: String, start: Long, end: Long?, routine: Boolean, timezone: String, dashboard: Boolean): Response<List<Event>> = error("no se usa")
        override suspend fun tasks(auth: String, dashboard: Boolean): Response<List<Task>> = error("no se usa")
        override suspend fun forecast(url: String): Response<Forecast> = error("no se usa")
        override suspend fun geocode(url: String): Response<GeoResponse> = error("no se usa")
    }

    private val api = FakeApi()
    private var clock = 1_000_000L
    private val today = LocalDate.of(2026, 11, 24)

    private fun repository() = MealRepository(api, DiskCache(folder.root), now = { clock })

    @Test
    fun downloadsAndSurvivesRestart() = runBlocking {
        val result = repository().refresh("token", today)
        assertEquals("Bearer token", api.auth)
        assertEquals("Lentejas", result.getOrThrow().items?.single()?.title)
        assertEquals("Lentejas", repository().meals.value?.items?.single()?.title)
    }

    @Test
    fun offlineKeepsTheCachedMenu() = runBlocking {
        val repository = repository()
        repository.refresh("token", today)
        clock += MealRepository.MAX_AGE_MS
        assertTrue(repository.isStale(today))
        api.failure = IOException("sin red")
        assertTrue(repository.refresh("token", today).isFailure)
        assertEquals("Lentejas", repository.meals.value?.items?.single()?.title)
        assertEquals("Lentejas", repository().meals.value?.items?.single()?.title)
    }

    @Test
    fun expiredSessionIsReportedAsUnauthorized() = runBlocking {
        api.status = 401
        val error = repository().refresh("token", today).exceptionOrNull()
        assertTrue(error?.isUnauthorized == true)
        assertNull(repository().meals.value)
    }

    @Test
    fun forbiddenHidesTheCopyAndStopsRetrying() = runBlocking {
        val repository = repository()
        repository.refresh("token", today)
        clock += MealRepository.MAX_AGE_MS
        assertTrue(repository.isStale(today))
        api.status = 403
        val error = repository.refresh("token", today).exceptionOrNull()
        assertTrue(error != null && !error.isUnauthorized)
        assertNull(repository.meals.value)
        assertNull(repository().meals.value)
        // El bucle de 60 s no vuelve a pedirlo ese día, ni mucho tiempo después
        clock += 10 * MealRepository.MAX_AGE_MS
        assertFalse(repository.isStale(today))
        // Otro día sí
        assertTrue(repository.isStale(today.plusDays(1)))
    }

    @Test
    fun missingHomeHeaderStopsRetryingUntilClear() = runBlocking {
        val repository = repository()
        api.status = 400
        repository.refresh("token", today)
        assertFalse(repository.isStale(today))
        repository.clear()
        assertTrue(repository.isStale(today))
    }

    @Test
    fun noPlanIsStoredAsEmptyMenu() = runBlocking {
        api.meals = MealsToday(has_plan = false, date = "2026-11-24", now_local = "13:00", items = emptyList())
        repository().refresh("token", today)
        val cached = repository().meals.value
        assertFalse(cached!!.has_plan)
        assertTrue(cached.items.orEmpty().isEmpty())
    }

    @Test
    fun newDayReplacesYesterdaysCopy() = runBlocking {
        val repository = repository()
        repository.refresh("token", today)
        api.meals = api.meals.copy(date = "2026-11-25")
        repository.refresh("token", today.plusDays(1))
        assertEquals("2026-11-25", repository().meals.value?.date)
        assertEquals(listOf("meals-2026-11-25"), DiskCache(folder.root).keys("meals-"))
    }

    @Test
    fun clearForgetsEverything() = runBlocking {
        val repository = repository()
        repository.refresh("token", today)
        repository.clear()
        assertNull(repository.meals.value)
        assertNull(repository().meals.value)
    }
}
