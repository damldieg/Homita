package com.dld.homita.dashboard.data

import org.junit.Assert.assertTrue
import org.junit.Test

/** La previsión pide 8 días y la sensación térmica, actual y por horas (dashboard-hoy-legible). */
class ForecastUrlTest {
    private val url = Api.forecastUrl(Location("Madrid", "", 40.4165, -3.70256))

    @Test
    fun `pide la sensacion termica en actual y por horas`() {
        assertTrue(url.contains("current=") && url.substringAfter("current=").substringBefore("&").contains("apparent_temperature"))
        assertTrue(url.substringAfter("hourly=").substringBefore("&").contains("apparent_temperature"))
    }

    @Test
    fun `pide 8 dias y no 14`() {
        assertTrue(url.contains("forecast_days=8"))
    }
}
