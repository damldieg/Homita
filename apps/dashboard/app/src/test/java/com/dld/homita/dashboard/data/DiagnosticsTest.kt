package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.IOException

/** Diagnóstico de datos (N6): último correcto y último error por endpoint. */
class DiagnosticsTest {
    private var now = 1_000L
    private val diagnostics = Diagnostics { now }

    @Test
    fun `guarda el ultimo correcto y el ultimo error por separado`() {
        diagnostics.record("menú de hoy", Result.success("ok"))
        now = 5_000L
        diagnostics.record("menú de hoy", Result.failure<String>(HttpError(403)))
        val entry = diagnostics.snapshot()["menú de hoy"]!!
        assertEquals(1_000L, entry.lastOkAt)
        assertEquals("HTTP 403", entry.lastError)
        assertEquals(5_000L, entry.lastErrorAt)
    }

    @Test
    fun `un correcto despues de un error borra el error`() {
        diagnostics.record("tiempo", Result.failure<String>(IOException("sin red")))
        now = 9_000L
        diagnostics.record("tiempo", Result.success("ok"))
        val entry = diagnostics.snapshot()["tiempo"]!!
        assertNull(entry.lastError)
        assertEquals(9_000L, entry.lastOkAt)
    }

    @Test
    fun `describe usa el codigo HTTP o el tipo de error`() {
        assertEquals("HTTP 401", Diagnostics.describe(HttpError(401)))
        assertEquals("IOException", Diagnostics.describe(IOException("x")))
    }
}
