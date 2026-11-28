package com.dld.homita.dashboard.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.MealWeekGrid
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/**
 * Menú de la semana (dashboard-menu-semanal): la rejilla día × franja, como la pestaña Menú de iOS, en solo lectura.
 * Editar, comprobar alergias y aceptar siguen en la app de control: el marco solo enseña lo que hay.
 */
@Composable
fun MenuScreen(state: UiState, onShift: (Int) -> Unit) {
    val monday = state.mealWeekStart ?: MealWeekGrid.mondayOf(LocalDate.now())
    val days = MealWeekGrid.days(monday)
    val items = state.mealWeek?.items.orEmpty()
    val slots = MealWeekGrid.slots(items)
    Column(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 32.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                "Menú de la semana · ${days.first().dayOfMonth} ${if (days.first().month == days.last().month) "" else monthName(days.first()) + " "}al ${days.last().dayOfMonth} ${monthName(days.last())}",
                style = Type.Title,
                color = Palette.Ink
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Arrow("‹") { onShift(-1) }
                Arrow("›") { onShift(1) }
            }
        }
        if (state.mealWeekFailed) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No se pudo cargar el menú. Cambia de semana con ‹ › para volver a intentarlo.", style = Type.Body.copy(color = Palette.InkMuted), textAlign = TextAlign.Center)
            }
            return@Column
        }
        if (state.mealWeek == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Cargando el menú…", style = Type.Body.copy(color = Palette.InkMuted))
            }
            return@Column
        }
        if (items.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Sin menú planificado para esta semana", style = Type.Body.copy(color = Palette.InkMuted))
            }
            return@Column
        }
        Row(Modifier.fillMaxWidth()) {
            Box(Modifier.width(170.dp))
            days.forEach { day ->
                Text(
                    day.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale("es", "ES")).replaceFirstChar { it.uppercase() } + " " + day.dayOfMonth,
                    style = Type.Small.copy(color = Palette.InkSoft),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        slots.forEach { slot ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    slotTitle(slot),
                    style = Type.Small.copy(color = Palette.InkSoft),
                    modifier = Modifier.width(170.dp)
                )
                days.forEach { day ->
                    val text = MealWeekGrid.cell(items, day, slot)
                    Box(Modifier.weight(1f).padding(4.dp), contentAlignment = Alignment.Center) {
                        Text(
                            text ?: "—",
                            style = Type.Body.copy(color = if (text == null) Palette.InkMuted else Palette.Ink),
                            textAlign = TextAlign.Center,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Arrow(label: String, onClick: () -> Unit) {
    Box(Modifier.size(56.dp).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Text(label, style = Type.Title, color = Palette.Ink)
    }
}

private fun monthName(date: LocalDate): String =
    date.month.getDisplayName(TextStyle.FULL, Locale("es", "ES"))

private fun slotTitle(slot: String): String = when (slot) {
    "breakfast" -> "Desayuno"
    "midmorning" -> "Media mañana"
    "lunch" -> "Comida"
    "snack" -> "Merienda"
    "dinner" -> "Cena"
    else -> slot
}
