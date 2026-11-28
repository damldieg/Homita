package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Agrupación de la compra por sección (dashboard-menu-semanal): orden de la tienda y sección desconocida a «otros». */
class ShoppingSectionsTest {
    private fun item(label: String, section: String?, state: String? = "pending") =
        ShoppingWebItem(label = label, section = section, state = state)

    @Test
    fun laCompraSeAgrupaEnElOrdenDeLaTienda() {
        val groups = ShoppingSections.group(listOf(item("Pan", "panaderia"), item("Tomate", "verdura"), item("Leche", "lacteos")))
        assertEquals(listOf("verdura", "lacteos", "panaderia"), groups.map { it.first })
    }

    @Test
    fun unaSeccionDesconocidaVaAOtros() {
        val groups = ShoppingSections.group(listOf(item("Cosa rara", "inventada"), item("Sin sección", null)))
        assertEquals(listOf("otros"), groups.map { it.first })
        assertEquals(2, groups.single().second.size)
    }

    @Test
    fun soloLoCompradoCuentaComoHecho() {
        assertTrue(ShoppingSections.isDone(item("A", "fruta", "checked")))
        assertFalse(ShoppingSections.isDone(item("B", "fruta", "skipped")))
        assertFalse(ShoppingSections.isDone(item("C", "fruta", "pending")))
    }

    @Test
    fun elTituloEsEnEspanol() {
        assertEquals("Lácteos", ShoppingSections.title("lacteos"))
        assertEquals("Otros", ShoppingSections.title("otros"))
    }

    @Test
    fun loQueYaTenemosNoSeListaPeroSiCuentaEnElResumen() {
        val items = listOf(item("Pan", "panaderia"), item("Queso", "lacteos", "skipped"), item("Leche", "lacteos", "checked"))
        assertEquals(listOf("Leche", "Pan"), ShoppingSections.group(items).flatMap { it.second }.map { it.label })
        val resumen = ShoppingSections.summary(items)
        assertEquals(1, resumen.pending)
        assertEquals(1, resumen.done)
        assertEquals(1, resumen.skipped)
        assertEquals(2, resumen.total)
    }

    @Test
    fun lasSeccionesSeReparteEnTresColumnasEquilibradas() {
        val items = (1..6).map { item("A$it", "verdura") } + (1..2).map { item("B$it", "fruta") } + listOf(item("C", "carne"), item("D", "pescado"))
        val columnas = ShoppingSections.columns(ShoppingSections.group(items), 3)
        assertEquals(3, columnas.size)
        // Cada sección entera en una sola columna
        val secciones = columnas.flatten().map { it.first }
        assertEquals(listOf("verdura", "fruta", "carne", "pescado"), secciones.sortedBy { listOf("verdura", "fruta", "carne", "pescado").indexOf(it) })
        assertEquals(4, secciones.size)
        assertEquals(setOf("verdura"), columnas[0].map { it.first }.toSet())
    }

    @Test
    fun paraSoloEnLosDeOrigenMenuYSinRepetirPlatos() {
        val delMenu = ShoppingWebItem(label = "Tomate", origin = "menu", sources = listOf(
            ShoppingWebSource("Ensalada"), ShoppingWebSource("Pizza"), ShoppingWebSource("Ensalada")))
        assertEquals("Ensalada, Pizza", ShoppingSections.forWhom(delMenu))
        assertEquals(null, ShoppingSections.forWhom(ShoppingWebItem(label = "Pan", origin = "manual")))
    }

    @Test
    fun cantidadesConComaDecimalYSinCerosSobrantes() {
        assertEquals("0,5 kg", ShoppingSections.quantity(ShoppingWebItem(quantity = 0.5, unit = "kg")))
        assertEquals("2 ud", ShoppingSections.quantity(ShoppingWebItem(quantity = 2.0, unit = "ud")))
        assertEquals("500 g", ShoppingSections.quantity(ShoppingWebItem(quantity = 500.0, unit = "g")))
        assertEquals(null, ShoppingSections.quantity(ShoppingWebItem(quantity = null, unit = "kg")))
    }

    @Test
    fun laVentanaManda_SobreLaColaYLaColaSobreLaLista() {
        val items = listOf(ShoppingWebItem(id = 1, label = "Pan", state = "pending"), ShoppingWebItem(id = 2, label = "Leche", state = "checked"))
        val cola = mapOf(1L to ShoppingCheck(1, true, "a", 1L), 2L to ShoppingCheck(2, false, "b", 1L))
        val ventana = mapOf(2L to ShoppingCheck(2, true, "c", 2L))
        val vistos = ShoppingSections.withOverlay(items, ShoppingSections.overlay(cola, ventana))
        assertEquals("checked", vistos.first { it.id == 1L }.state)
        assertEquals("checked", vistos.first { it.id == 2L }.state)
    }
}
