package com.dld.homita.dashboard.data.repository

import com.dld.homita.dashboard.data.Api
import com.dld.homita.dashboard.data.HttpError
import com.dld.homita.dashboard.data.MealsToday
import com.dld.homita.dashboard.data.bodyOrThrow
import com.dld.homita.dashboard.data.cache.CachedResource
import com.dld.homita.dashboard.data.cache.DiskCache
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.LocalDate

/**
 * Menú de hoy (`GET /meal/today`), con su copia en disco por fecha local (`meals-<fecha>`). Solo se conserva el del
 * día más reciente: al descargar el de un día nuevo se borran los anteriores, así que pasada la medianoche sin red no
 * se enseña el menú de ayer (el de la copia no coincide con hoy y la tarjeta se oculta).
 */
class MealRepository(
    private val api: Api,
    private val cache: DiskCache,
    private val now: () -> Long = System::currentTimeMillis
) {
    private val resources = mutableMapOf<LocalDate, CachedResource<MealsToday>>()
    private val _meals = MutableStateFlow<MealsToday?>(null)

    /** Último menú disponible (en caché o descargado). Compara su `date` con hoy antes de usarlo. */
    val meals: StateFlow<MealsToday?> = _meals

    init {
        cache.keys(PREFIX).mapNotNull { key -> runCatching { LocalDate.parse(key.removePrefix(PREFIX)) }.getOrNull() }
            .maxOrNull()
            ?.let { latest -> _meals.value = resource(latest).data.value?.value }
    }

    /** Día en que el servidor negó el menú (403 sin `menu.view`, 400 sin hogar): no se reintenta hasta otro día o `clear()`. */
    private var deniedDay: LocalDate? = null

    /** Si hay que volver a pedirlo. Con el menú denegado hoy, nunca (el bucle de 60 s no repite la petición). */
    fun isStale(today: LocalDate) = deniedDay != today && resource(today).isStale()

    suspend fun refresh(token: String, today: LocalDate): Result<MealsToday> {
        val result = resource(today).refresh { api.mealsToday(bearer(token)).bodyOrThrow() }
        result.onSuccess { meals ->
            _meals.value = meals
            resources.keys.filter { it != today }.forEach { old ->
                resources.remove(old)?.clear()
            }
            cache.keys(PREFIX).filter { it != PREFIX + today }.forEach { cache.remove(it) }
        }
        result.onFailure { error ->
            if (error is HttpError && (error.code == 403 || error.code == 400)) deny(today)
        }
        return result
    }

    /** Sin permiso o sin hogar: se olvida la copia (la tarjeta se oculta, como en iOS) y se recuerda el día. */
    private fun deny(today: LocalDate) {
        deniedDay = today
        _meals.value = null
        resources.values.forEach { it.clear() }
        resources.clear()
        cache.keys(PREFIX).forEach { cache.remove(it) }
    }

    fun clear() {
        deniedDay = null
        resources.values.forEach { it.clear() }
        resources.clear()
        cache.keys(PREFIX).forEach { cache.remove(it) }
        _meals.value = null
    }

    private fun resource(day: LocalDate): CachedResource<MealsToday> = resources.getOrPut(day) {
        CachedResource(cache, PREFIX + day, MealsToday::class.java, MAX_AGE_MS, now)
    }

    companion object {
        const val MAX_AGE_MS = 5 * 60_000L
        private const val PREFIX = "meals-"
    }
}
