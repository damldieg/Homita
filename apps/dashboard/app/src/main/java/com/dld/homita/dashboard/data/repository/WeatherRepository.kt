package com.dld.homita.dashboard.data.repository

import com.dld.homita.dashboard.data.Api
import com.dld.homita.dashboard.data.Forecast
import com.dld.homita.dashboard.data.Location
import com.dld.homita.dashboard.data.bodyOrThrow
import com.dld.homita.dashboard.data.withDailyFromHourly
import com.dld.homita.dashboard.data.cache.Cached
import com.dld.homita.dashboard.data.cache.CachedResource
import com.dld.homita.dashboard.data.cache.DiskCache
import kotlinx.coroutines.flow.StateFlow

/** Previsión de Open-Meteo para la ubicación elegida: el día anterior y 14 días. */
class WeatherRepository(private val api: Api, cache: DiskCache) {
    private val resource = CachedResource<Forecast>(cache, "forecast", Forecast::class.java, MAX_AGE_MS)

    val forecast: StateFlow<Cached<Forecast>?> = resource.data

    fun isStale() = resource.isStale()

    suspend fun refresh(location: Location): Result<Forecast> = resource.refresh {
        api.forecast(Api.forecastUrl(location)).bodyOrThrow().withDailyFromHourly()
    }

    /** Al cambiar de ubicación: la previsión anterior ya no sirve. */
    fun clear() = resource.clear()

    companion object {
        const val MAX_AGE_MS = 30 * 60_000L
    }
}
