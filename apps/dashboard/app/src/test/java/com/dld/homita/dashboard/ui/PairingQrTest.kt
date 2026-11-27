package com.dld.homita.dashboard.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** QR de vinculación (dashboard-vinculacion-qr): la matriz es cuadrada, determinista y los píxeles son blanco o negro. */
class PairingQrTest {
    @Test
    fun laMatrizEsCuadradaYDeterministaParaElMismoCodigo() {
        val a = PairingQr.matrix("584965")
        val b = PairingQr.matrix("584965")
        assertEquals(a.width, a.height)
        assertEquals(a.width, b.width)
        for (y in 0 until a.height) for (x in 0 until a.width) assertEquals(a.get(x, y), b.get(x, y))
    }

    @Test
    fun losPixelesEscaladosSonBlancoONegroYDelTamanoPedido() {
        val matrix = PairingQr.matrix("123456")
        val scale = 10
        val pixels = PairingQr.pixels(matrix, matrix.width * scale)
        assertEquals((matrix.width * scale) * (matrix.width * scale), pixels.size)
        assertTrue(pixels.all { it == 0xFF000000.toInt() || it == 0xFFFFFFFF.toInt() })
        assertTrue("tiene negro y blanco", pixels.any { it == 0xFF000000.toInt() } && pixels.any { it == 0xFFFFFFFF.toInt() })
    }

    @Test
    fun codigosDistintosDanQrDistintos() {
        val a = PairingQr.matrix("111111")
        val b = PairingQr.matrix("222222")
        val differs = (0 until a.height).any { y -> (0 until a.width).any { x -> a.get(x, y) != b.get(x, y) } }
        assertTrue(differs)
    }
}
