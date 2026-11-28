package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/** Rejilla de la semana del menú (dashboard-menu-semanal): lunes, días, orden de franjas y casillas. */
class MealWeekGridTest {
    private val monday = LocalDate.of(2026, 11, 23)

    private fun item(day: LocalDate, slot: String, title: String, position: Int = 0) =
        MealPlanWeekItem(day.toString(), slot, position, "recipe", title)

    @Test
    fun elLunesEsDeLaSemanaDeCualquierDia() {
        assertEquals(monday, MealWeekGrid.mondayOf(LocalDate.of(2026, 11, 25)))
        assertEquals(monday, MealWeekGrid.mondayOf(monday))
    }

    @Test
    fun laSemanaTieneSieteDiasDesdeElLunes() {
        val days = MealWeekGrid.days(monday)
        assertEquals(7, days.size)
        assertEquals(monday, days.first())
        assertEquals(LocalDate.of(2026, 11, 29), days.last())
    }

    @Test
    fun lasFranjasSeOrdenanComoElDia() {
        val items = listOf(
            item(monday, "dinner", "Sopa"),
            item(monday, "breakfast", "Tostadas"),
            item(monday, "lunch", "Lentejas"),
        )
        assertEquals(listOf("breakfast", "lunch", "dinner"), MealWeekGrid.slots(items))
    }

    @Test
    fun unaCasillaJuntaSusPlatosPorPosicion() {
        val items = listOf(
            item(monday, "lunch", "Ensalada", position = 1),
            item(monday, "lunch", "Pollo", position = 0),
        )
        assertEquals("Pollo · Ensalada", MealWeekGrid.cell(items, monday, "lunch"))
    }

    @Test
    fun unaCasillaVaciaDaNull() {
        val items = listOf(item(monday, "lunch", "Lentejas"))
        assertNull(MealWeekGrid.cell(items, monday.plusDays(1), "lunch"))
        assertNull(MealWeekGrid.cell(items, monday, "dinner"))
    }
}
