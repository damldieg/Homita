package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** «Actualizado hace X» y «Sin conexión» en la barra (U7). */
class FreshnessTest {
    private val now = 10_000_000_000L
    private fun ago(minutes: Long) = now - minutes * 60_000L

    @Test
    fun `datos recientes y con red no muestran nada`() {
        assertNull(Freshness.label(ago(5), now, online = true, connected = true))
        assertNull(Freshness.label(ago(14), now, online = true, connected = true))
    }

    @Test
    fun `mas de 15 minutos dice cuanto`() {
        assertEquals("Actualizado hace 20 min", Freshness.label(ago(20), now, online = true, connected = true))
        assertEquals("Actualizado hace 2 h", Freshness.label(ago(130), now, online = true, connected = true))
        assertEquals("Actualizado hace 1 día", Freshness.label(ago(30 * 60), now, online = true, connected = true))
        assertEquals("Actualizado hace 3 días", Freshness.label(ago(3 * 24 * 60), now, online = true, connected = true))
    }

    @Test
    fun `sin red o con el ultimo intento fallido dice sin conexion`() {
        assertEquals("Sin conexión", Freshness.label(ago(1), now, online = true, connected = false))
        assertEquals("Sin conexión · Actualizado hace 3 h", Freshness.label(ago(180), now, online = false, connected = true))
    }

    @Test
    fun `sin copia no hay tiempo que enseñar`() {
        assertNull(Freshness.label(null, now, online = true, connected = true))
    }
}
