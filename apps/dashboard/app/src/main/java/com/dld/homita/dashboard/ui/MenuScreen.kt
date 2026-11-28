package com.dld.homita.dashboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.MealPlanWeekItem
import com.dld.homita.dashboard.data.MealWeekGrid
import com.dld.homita.dashboard.data.ShoppingSections
import com.dld.homita.dashboard.data.ShoppingSummary
import com.dld.homita.dashboard.data.ShoppingWebItem
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type
import java.time.LocalDate
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

private val PanelShape = RoundedCornerShape(20.dp)
private val LineColor = Palette.Line

/** Vistas de Menú: la semana (tabla) y la compra del hogar. */
private enum class MenuView { Week, Shopping }

/**
 * Menú (dashboard-menu-semanal, dashboard-menu-compra fase A): la semana en tabla y la compra del hogar, con un selector
 * entre las dos. Solo lectura: editar, comprobar alergias y aceptar siguen en la app de control.
 */
@Composable
fun MenuScreen(state: UiState, onShift: (Int) -> Unit) {
    var view by rememberSaveable { mutableStateOf(MenuView.Week) }
    val current = MealWeekGrid.weekStartOf(LocalDate.now(), state.weekStartDay)
    val monday = state.mealWeekStart ?: current
    val days = MealWeekGrid.days(monday)
    Column(
        Modifier.fillMaxSize().padding(horizontal = 32.dp, vertical = 28.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Header(view, { view = it }, state, days, current, onShift)
        when (view) {
            MenuView.Week -> WeekPanel(state, days, Modifier.fillMaxWidth().weight(1f))
            MenuView.Shopping -> ShoppingView(state, Modifier.fillMaxWidth().weight(1f))
        }
    }
}

@Composable
private fun Header(
    view: MenuView,
    onView: (MenuView) -> Unit,
    state: UiState,
    days: List<LocalDate>,
    current: LocalDate,
    onShift: (Int) -> Unit
) {
    val pending = ShoppingSections.summary(state.shopping?.items.orEmpty()).pending
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Column {
            Text(if (view == MenuView.Week) "Menú de la semana" else "Compra", style = Type.Title)
            Text(
                if (view == MenuView.Week) rangeLabel(days) else "$pending por comprar",
                style = Type.Small
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            if (view == MenuView.Week) {
                val weeksAway = ChronoUnit.WEEKS.between(days.first(), current).toInt()
                if (weeksAway != 0) {
                    Pill("Volver a esta semana", primary = true) { onShift(weeksAway) }
                }
            }
            Row(
                Modifier.clip(RoundedCornerShape(50)).border(1.dp, Palette.CardBorder, RoundedCornerShape(50)).background(Palette.Card),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Segment("Semana", selected = view == MenuView.Week) { onView(MenuView.Week) }
                Segment("Compra", selected = view == MenuView.Shopping, badge = pending.takeIf { it > 0 }) { onView(MenuView.Shopping) }
            }
            if (view == MenuView.Week) {
                val offset = ChronoUnit.WEEKS.between(current, days.first()).toInt()
                Row(
                    Modifier.clip(RoundedCornerShape(50)).border(1.dp, Palette.CardBorder, RoundedCornerShape(50)).background(Palette.Card),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Arrow("‹", enabled = offset > -1) { onShift(-1) }
                    Box(Modifier.width(1.dp).height(28.dp).background(LineColor))
                    Arrow("›", enabled = offset < 2) { onShift(1) }
                }
            }
        }
    }
}

@Composable
private fun Segment(label: String, selected: Boolean, badge: Int? = null, onClick: () -> Unit) {
    Row(
        Modifier
            .height(64.dp)
            .clip(RoundedCornerShape(50))
            .background(if (selected) Palette.Ink else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(label, style = Type.Small.copy(color = if (selected) Palette.Card else Palette.Ink, fontWeight = FontWeight.Medium))
        badge?.let {
            Box(
                Modifier.clip(CircleShape).background(Palette.Sage).padding(horizontal = 10.dp, vertical = 2.dp),
                contentAlignment = Alignment.Center
            ) { Text("$it", style = Type.Tiny.copy(color = Palette.Card, fontWeight = FontWeight.SemiBold)) }
        }
    }
}

@Composable
private fun Pill(label: String, primary: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .height(64.dp)
            .clip(RoundedCornerShape(50))
            .background(if (primary) Palette.Ink else Palette.Card)
            .clickable(onClick = onClick)
            .padding(horizontal = 28.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(label, style = Type.Small.copy(color = if (primary) Palette.Card else Palette.Ink, fontWeight = FontWeight.Medium))
    }
}

@Composable
private fun Arrow(label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(64.dp).alpha(if (enabled) 1f else 0.3f).then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center
    ) {
        Text(label, style = Type.Large.copy(fontWeight = FontWeight.Medium))
    }
}

/** Panel de la semana: la tabla, o el estado (cargando, error, borrador, sin plan). */
@Composable
private fun WeekPanel(state: UiState, days: List<LocalDate>, modifier: Modifier) {
    Box(modifier.background(Palette.Card, PanelShape).border(1.dp, Palette.CardBorder, PanelShape).clip(PanelShape)) {
        val plan = state.mealWeek
        val items = plan?.items.orEmpty()
        when {
            state.mealWeekFailed -> Centered("No se pudo cargar el menú", "Cambia de semana para volver a intentarlo.")
            plan == null -> Centered("Cargando el menú…")
            plan.status == "draft" -> Centered("El menú de esta semana está en preparación", "Aparecerá aquí cuando se acepte en la app.")
            items.isEmpty() -> Centered("Sin menú esta semana", "Planifícalo desde la app Homita.")
            else -> WeekTable(days, MealWeekGrid.visibleSlots(items, state.enabledSlots), items)
        }
    }
}

@Composable
private fun WeekTable(days: List<LocalDate>, slots: List<String>, items: List<MealPlanWeekItem>) {
    val today = LocalDate.now()
    Column(Modifier.fillMaxSize()) {
        // Cabecera: esquina vacía y un día por columna; el de hoy resaltado.
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Cell(Modifier.width(LABEL_WIDTH), background = Palette.Highlight) { }
            days.forEach { day ->
                val isToday = day == today
                Cell(Modifier.weight(1f), background = if (isToday) Palette.Accent.copy(alpha = 0.12f) else Palette.Highlight) {
                    Text(
                        day.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale("es", "ES")).replaceFirstChar { it.uppercase() },
                        style = Type.Tiny.copy(color = if (isToday) Palette.Accent else Palette.InkSoft)
                    )
                    Text(
                        day.dayOfMonth.toString(),
                        style = Type.Large.copy(fontWeight = FontWeight.SemiBold, color = if (isToday) Palette.Accent else Palette.Ink)
                    )
                }
            }
        }
        slots.forEach { slot ->
            // Comida y cena pesan más que desayuno y merienda: la tabla llena el alto y los platos respiran.
            val weight = if (slot == "lunch" || slot == "dinner") 1.2f else 0.8f
            Row(Modifier.fillMaxWidth().weight(weight)) {
                Cell(Modifier.width(LABEL_WIDTH), background = Palette.Highlight) {
                    Text(slotTitle(slot), style = Type.Small.copy(fontWeight = FontWeight.SemiBold, color = Palette.Ink))
                }
                days.forEach { day ->
                    val item = items.firstOrNull { it.day == day.toString() && it.slot == slot }
                    val text = MealWeekGrid.cell(items, day, slot)
                    val kind = item?.kind
                    val past = day.isBefore(today)
                    Cell(
                        Modifier.weight(1f).then(if (past) Modifier.alpha(0.6f) else Modifier),
                        background = if (day == today) Palette.Accent.copy(alpha = 0.04f) else Color.Transparent
                    ) {
                        Text(
                            text ?: "",
                            style = Type.Body.copy(
                                fontSize = 24.sp,
                                lineHeight = 30.sp,
                                color = if (kind == "eat_out") Palette.Sage else Palette.Ink,
                                fontStyle = if (kind == "eat_out") FontStyle.Italic else FontStyle.Normal
                            ),
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

/** Celda de la tabla: fondo opcional y línea fina a la derecha y abajo para formar la rejilla. */
@Composable
private fun Cell(modifier: Modifier, background: Color, content: @Composable () -> Unit) {
    Column(
        modifier
            .fillMaxHeight()
            .background(background)
            .border(1.dp, LineColor)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) { content() }
}

/** Vista de compra: tres columnas con las secciones enteras a la izquierda y el resumen a la derecha. */
@Composable
private fun ShoppingView(state: UiState, modifier: Modifier) {
    val list = state.shopping
    val items = list?.items.orEmpty()
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
        Box(Modifier.weight(2f).fillMaxHeight().background(Palette.Card, PanelShape).border(1.dp, Palette.CardBorder, PanelShape).clip(PanelShape)) {
            when {
                state.shoppingFailed -> Centered("No se pudo cargar la compra")
                list == null -> Centered("Cargando la compra…")
                ShoppingSections.listed(items).isEmpty() -> Centered("La compra está vacía", "Acepta el menú de la semana o añade algo desde la app.")
                else -> ShoppingColumns(ShoppingSections.columns(ShoppingSections.group(items), 3))
            }
        }
        SummaryPanel(ShoppingSections.summary(items), Modifier.weight(1f).fillMaxHeight())
    }
}

@Composable
private fun ShoppingColumns(columns: List<List<Pair<String, List<ShoppingWebItem>>>>) {
    Row(Modifier.fillMaxSize().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        columns.forEach { column ->
            Column(Modifier.weight(1f).fillMaxHeight().verticalScroll(rememberScrollState())) {
                column.forEach { (section, group) ->
                    Row(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            ShoppingSections.title(section).uppercase(),
                            style = Type.Tiny.copy(color = Palette.Accent, fontWeight = FontWeight.SemiBold),
                            modifier = Modifier.weight(1f)
                        )
                        Text("${group.count { !ShoppingSections.isDone(it) }}", style = Type.Tiny.copy(color = Palette.InkMuted))
                    }
                    group.forEach { ShoppingRow(it) }
                }
            }
        }
    }
}

@Composable
private fun ShoppingRow(item: ShoppingWebItem) {
    val done = ShoppingSections.isDone(item)
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(34.dp)
                .border(2.dp, if (done) Palette.Sage else Palette.InkMuted, CircleShape)
                .background(if (done) Palette.Sage else Color.Transparent, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (done) Text("✓", style = Type.Tiny.copy(color = Palette.Card, fontWeight = FontWeight.Bold))
        }
        Column(Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                item.label.orEmpty(),
                style = Type.Body.copy(
                    fontSize = 22.sp,
                    lineHeight = 28.sp,
                    color = if (done) Palette.InkMuted else Palette.Ink,
                    textDecoration = if (done) TextDecoration.LineThrough else null
                ),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            ShoppingSections.forWhom(item)?.let {
                Text("Para: $it", style = Type.Tiny.copy(color = Palette.InkMuted), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        ShoppingSections.quantity(item)?.let {
            Text(it, style = Type.Small, maxLines = 1, softWrap = false, modifier = Modifier.padding(start = 8.dp, end = 8.dp))
        }
    }
}

/** Resumen de la compra: lo que queda, el progreso y de dónde viene. */
@Composable
private fun SummaryPanel(summary: ShoppingSummary, modifier: Modifier) {
    Column(
        modifier
            .background(Palette.Card, PanelShape)
            .border(1.dp, Palette.CardBorder, PanelShape)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Resumen", style = Type.Large)
        Text("${summary.pending}", style = Type.Huge.copy(fontSize = 96.sp, lineHeight = 96.sp, color = Palette.Ink))
        Text(
            when {
                summary.total == 0 -> "Nada en la lista"
                summary.pending == 0 -> "Todo comprado"
                else -> "por comprar"
            },
            style = Type.Small
        )
        // Progreso: comprados frente al total de la lista.
        Row(Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(6.dp)).background(LineColor)) {
            if (summary.done > 0) Box(Modifier.weight(summary.done.toFloat()).fillMaxHeight().background(Palette.Sage))
            if (summary.pending > 0) Box(Modifier.weight(summary.pending.toFloat()).fillMaxHeight())
        }
        Text("${summary.done} de ${summary.total} comprados", style = Type.Small)
        Text("Del menú: ${summary.fromMenu} · A mano: ${summary.manual}", style = Type.Small)
        Text("Ya lo tenéis: ${summary.skipped}", style = Type.Small)
        Text(
            "Para añadir o cambiar cantidades, usa la app Homita.",
            style = Type.Tiny.copy(color = Palette.InkMuted),
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@Composable
private fun Centered(title: String, subtitle: String? = null) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(title, style = Type.Large.copy(color = Palette.InkSoft), textAlign = TextAlign.Center)
        subtitle?.let { Text(it, style = Type.Small.copy(color = Palette.InkMuted), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp)) }
    }
}

private val LABEL_WIDTH = 150.dp

private fun rangeLabel(days: List<LocalDate>): String {
    val first = days.first()
    val last = days.last()
    val month = { d: LocalDate -> d.month.getDisplayName(TextStyle.FULL, Locale("es", "ES")) }
    return if (first.month == last.month) {
        "${first.dayOfMonth} al ${last.dayOfMonth} de ${month(last)}"
    } else {
        "${first.dayOfMonth} de ${month(first)} al ${last.dayOfMonth} de ${month(last)}"
    }
}

private fun slotTitle(slot: String): String = when (slot) {
    "breakfast" -> "Desayuno"
    "midmorning" -> "Media mañana"
    "lunch" -> "Comida"
    "snack" -> "Merienda"
    "dinner" -> "Cena"
    else -> slot
}
