package com.dld.homita.dashboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.EventAvailable
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.Thermostat
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.outlined.Weekend
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.Event
import com.dld.homita.dashboard.data.Forecast
import com.dld.homita.dashboard.data.MealsTodayState
import com.dld.homita.dashboard.data.MealsTodayView
import com.dld.homita.dashboard.data.Person
import com.dld.homita.dashboard.data.Task
import com.dld.homita.dashboard.data.TaskDue
import com.dld.homita.dashboard.data.TaskPriority
import com.dld.homita.dashboard.data.partitionEvents
import com.dld.homita.dashboard.data.priorityValue
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.TextStyle
import kotlin.math.roundToInt

private val Gap = 28.dp

/** Tiempo sin tocar la pantalla tras el que Agenda y Rutinas vuelven a su posición si se han deslizado a mano. */
private const val SCROLL_RESET_MILLIS = 60_000L

/** Días que se muestran en «Próximos 3 días», a partir de mañana (C2). */
private const val UPCOMING_DAYS = 3L

/** Filas de «Hoy se come»: todas las franjas del día (N5 le da sitio propio). */
private const val MEAL_ROWS = 6

/**
 * Hoy (propuesta A, dashboard-hoy-legible): arriba, la hora y lo siguiente con el aviso de vencimiento (izquierda) y el
 * tiempo en franja (derecha, toca para ver el detalle); abajo, la agenda de hoy como bloque principal (izquierda) y
 * a la derecha «Hoy se come», «Próximos 3 días» y las rutinas de hoy.
 */
@Composable
fun TodayScreen(state: UiState, lastTouch: Long, onOpenWeather: () -> Unit, onDismissDue: (String) -> Unit) {
    val due = state.content?.tasks?.let { TaskDue.banner(it, state.now, state.dismissedDue) }
    Box(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 32.dp)) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Gap)) {
            Row(Modifier.fillMaxWidth().weight(0.42f), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                ClockColumn(state, Modifier.weight(1f).fillMaxHeight())
                AlertsColumn(due, state.now, onDismissDue, Modifier.weight(1f).fillMaxHeight())
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    val forecast = state.forecast
                    val location = state.location
                    if (forecast != null && location != null) {
                        TodayWeather(forecast, location.name, state.now, onOpenWeather, Modifier.fillMaxSize())
                    } else {
                        Card(Modifier.fillMaxSize()) {
                            CardHeader("Tiempo", Icons.Outlined.Thermostat, Palette.Warm)
                            Text(if (location == null) "Elige una ubicación en Ajustes" else "Cargando previsión…", style = Type.Body.copy(color = Palette.InkMuted), modifier = Modifier.padding(top = 16.dp))
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().weight(0.58f), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                AgendaCard(state, lastTouch, Modifier.weight(1f).fillMaxHeight())
                Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(Gap)) {
                    MealsCard(state)
                    UpcomingDaysCard(state, lastTouch, Modifier.weight(1f).fillMaxWidth())
                    RoutinesCard(state, lastTouch, Modifier.weight(1f).fillMaxWidth())
                }
            }
        }
    }
}

/**
 * Cabecera del tiempo de hoy en su columna (un tercio de la pantalla): icono y temperatura, estado, mínima y máxima,
 * sensación térmica. Compacta: la gráfica de horas necesita el alto.
 */
@Composable
private fun TodayWeatherHeader(forecast: Forecast, location: String, now: LocalDateTime) {
    val today = now.toLocalDate()
    val day = forecast.dayIndex(today)
    val current = forecast.current
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            WeatherIcon(current.weather_code, current.is_day == 1, 64, animated = true)
            Text(current.temperature_2m.degrees(), style = Type.Huge.copy(fontSize = 80.sp, lineHeight = 80.sp, letterSpacing = (-3).sp), modifier = Modifier.padding(start = 12.dp))
            Text(weatherText(current.weather_code), style = Type.Body, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 12.dp).weight(1f))
        }
        Text(
            listOfNotNull(location, day.takeIf { it >= 0 }?.let { "Mín ${forecast.daily.temperature_2m_min[it].degrees()} · Máx ${forecast.daily.temperature_2m_max[it].degrees()}" }).joinToString("  ·  "),
            style = Type.Small,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        current.apparent_temperature?.let { Text("Sensación ${it.degrees()}", style = Type.Small, maxLines = 1) }
    }
}

/**
 * El tiempo de hoy en Hoy: la cabecera (ahora, mínima y máxima, sensación térmica) y las horas del día en una franja que
 * se desliza en horizontal, centrada en la hora actual. Solo hoy; los días siguientes están en la pantalla del tiempo,
 * que se abre tocando la tarjeta (fuera de la franja).
 */
@Composable
private fun TodayWeather(forecast: Forecast, location: String, now: LocalDateTime, onOpen: () -> Unit, modifier: Modifier) {
    val today = now.toLocalDate()
    Column(
        modifier
            .background(Palette.Card, RoundedCornerShape(32.dp))
            .padding(horizontal = 36.dp, vertical = 24.dp)
            .clickable(onClick = onOpen)
    ) {
        TodayWeatherHeader(forecast, location, now)
        HourlyForecast(forecast, now, Modifier.fillMaxWidth().weight(1f).padding(top = 12.dp), iconSize = 28, day = today, compact = true, hourWidth = 96.dp)
    }
}

@Composable
private fun Card(modifier: Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .background(Palette.Card, RoundedCornerShape(32.dp))
            .padding(horizontal = 34.dp, vertical = 28.dp),
        content = content
    )
}

// --- Hora, lo siguiente y el aviso de vencimiento (izquierda) ---

@Composable
private fun ClockColumn(state: UiState, modifier: Modifier) {
    val now = state.now
    val today = now.toLocalDate()
    val next = nextUp(state)
    Column(modifier) {
        Column(Modifier.fillMaxWidth().weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            FlipClock(if (state.clockValid) now.format(HourMinute) else "--:--", tile = 96.dp, height = 96.dp * (184f / 110f))
            Text(
                if (state.clockValid) "${today.weekdayName()} · ${today.dayOfMonth} ${today.month.getDisplayName(TextStyle.FULL, Spanish)}".uppercase(Spanish) else "SINCRONIZANDO HORA…",
                style = Type.Mono.copy(fontSize = 24.sp, letterSpacing = 5.sp, color = Palette.InkSoft),
                maxLines = 1,
                modifier = Modifier.padding(top = 24.dp)
            )
        }
        if (next != null) NextCard(next, now, Modifier.padding(top = 16.dp))
    }
}

/**
 * Avisos de vencimiento en su propia columna de arriba (dashboard-hoy-legible): el de la tarea de alta prioridad que vence
 * antes, o un «Sin avisos» tranquilo. Así el reloj no se recorta cuando hay uno.
 */
@Composable
private fun AlertsColumn(due: TaskDue.DueBanner?, now: LocalDateTime, onDismissDue: (String) -> Unit, modifier: Modifier) {
    Card(modifier) {
        CardHeader("Avisos", Icons.Outlined.Warning, Palette.Accent, count = if (due != null) 1 else null)
        if (due != null) {
            DueCard(due, now) { onDismissDue(due.key) }
        } else {
            EmptyState(Icons.Outlined.EventAvailable, Palette.Sage, "Sin avisos", "Nada vence pronto", Modifier.weight(1f).fillMaxWidth())
        }
    }
}

/**
 * Aviso de la tarea de prioridad alta que vence antes (N1–N4): vencida hasta completarse, con su fecha relativa
 * («Hoy 19:00», «Mañana 19:00», «vie 4 dic 19:00») y «Cerrar» con 64 px de área táctil; el cierre se recuerda.
 */
@Composable
private fun DueCard(due: TaskDue.DueBanner, now: LocalDateTime, onDismiss: () -> Unit) {
    val overdue = due.due.isBefore(now)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = 16.dp)
            .background(Palette.Accent.copy(alpha = 0.14f), RoundedCornerShape(28.dp))
            .padding(start = 26.dp, end = 12.dp, top = 14.dp, bottom = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(due.task.title, style = Type.Body, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                TaskDue.whenText(due.due, now),
                style = Type.Small.copy(color = if (overdue) Palette.Accent else Palette.InkSoft, fontWeight = if (overdue) FontWeight.SemiBold else FontWeight.Normal),
                maxLines = 1,
            )
        }
        Box(Modifier.heightIn(min = 64.dp).clickable(onClick = onDismiss).padding(horizontal = 18.dp), contentAlignment = Alignment.Center) {
            Text("Cerrar", style = Type.Small.copy(color = Palette.InkMuted, fontWeight = FontWeight.Medium))
        }
    }
}

/** Lo siguiente: el primer evento o sesión de rutina que aún no ha empezado, si es de hoy o de mañana. */
private fun nextUp(state: UiState): Event? {
    val content = state.content ?: return null
    val today = state.now.toLocalDate()
    val next = (content.events + content.sessions).filter { !it.at.isBefore(state.now) && !it.isOngoing(today) }.minByOrNull { it.at } ?: return null
    return next.takeIf { it.at.toLocalDate() <= state.now.toLocalDate().plusDays(1) }
}

/** Próximo evento en una tarjeta del color de su calendario: personas, lo que falta, título, día y hora. */
@Composable
private fun NextCard(event: Event, now: LocalDateTime, modifier: Modifier = Modifier) {
    val color = parseColor(event.calendar_color, Palette.Accent)
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .fillMaxWidth()
            .background(color, RoundedCornerShape(32.dp))
            .padding(horizontal = 30.dp, vertical = 24.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                event.persons.orEmpty().joinToString(", ") { it.name }.uppercase(Spanish),
                style = Type.Label.copy(color = Color.White.copy(alpha = 0.9f)),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Text(
                relativeBadge(now, event.at),
                style = Type.Small.copy(color = Color.White, fontWeight = FontWeight.SemiBold),
                maxLines = 1,
                modifier = Modifier
                    .padding(start = 16.dp)
                    .background(Color.White.copy(alpha = 0.2f), RoundedCornerShape(18.dp))
                    .padding(horizontal = 14.dp, vertical = 4.dp)
            )
        }
        Text(event.title, style = Type.Large.copy(color = Color.White, fontWeight = FontWeight.Medium), maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(
            "${relativeDay(event.at.toLocalDate(), now.toLocalDate())} · ${event.at.format(HourMinute)}",
            style = Type.Small.copy(color = Color.White.copy(alpha = 0.9f)),
            maxLines = 1
        )
    }
}

// --- Agenda de hoy (bloque principal) ---

/**
 * Agenda de hoy: los eventos de hoy (en curso arriba; los pasados en gris), sin el que ya está en «Lo siguiente».
 * Es el bloque principal de la pantalla: horas y títulos a 24 px o más.
 */
@Composable
private fun AgendaCard(state: UiState, lastTouch: Long, modifier: Modifier) {
    val now = state.now
    val today = now.toLocalDate()
    val parts = partitionEvents(state.content?.events.orEmpty(), now, nextUp(state))
    val todays = parts.upcoming.filter { it.at.toLocalDate() == today }
    Card(modifier) {
        CardHeader("Hoy", Icons.Outlined.Event, Palette.Rain, count = todays.count { !it.at.isBefore(now) } + parts.ongoing.size)
        if (parts.ongoing.isNotEmpty()) OngoingBlock(parts.ongoing)
        if (todays.isEmpty() && parts.ongoing.isEmpty()) {
            EmptyState(Icons.Outlined.EventAvailable, Palette.Rain, "Sin eventos hoy", "Día libre en los calendarios", Modifier.weight(1f).fillMaxWidth())
            return@Card
        }
        if (todays.isNotEmpty()) {
            UpcomingList(todays, now, lastTouch) { event ->
                EventRow(event, now)
                Hairline()
            }
        }
    }
}

/** «En curso»: eventos de varios días cuyo rango contiene hoy, con el rango «10 OCT → 20 OCT». */
@Composable
private fun OngoingBlock(events: List<Event>) {
    Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text(
            "EN CURSO",
            style = Type.Small.copy(color = Palette.InkSoft, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp),
            modifier = Modifier.padding(vertical = 6.dp)
        )
        events.forEach { event ->
            EventRow(event, event.at, ongoing = true)
            Hairline()
        }
    }
}

@Composable
private fun EventRow(event: Event, now: LocalDateTime, ongoing: Boolean = false) {
    val past = !ongoing && event.at.isBefore(now)
    val color = if (past) Palette.Line else parseColor(event.calendar_color)
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        Box(Modifier.width(7.dp).fillMaxHeight().background(color))
        Column(Modifier.weight(1f).padding(start = 18.dp, top = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (ongoing) "${event.at.toLocalDate().shortLabel()} → ${event.endDay?.shortLabel().orEmpty()}"
                    else event.at.format(HourMinute),
                    style = Type.Small.copy(color = if (past) Palette.InkMuted else Palette.Ink, fontWeight = FontWeight.SemiBold),
                    maxLines = 1,
                    modifier = Modifier.weight(1f)
                )
                if (!past && !ongoing) {
                    Text(
                        relativeBadge(now, event.at),
                        style = Type.Small.copy(color = Palette.InkSoft, fontWeight = FontWeight.SemiBold),
                        maxLines = 1,
                        modifier = Modifier.background(Palette.Highlight, RoundedCornerShape(16.dp)).padding(horizontal = 14.dp, vertical = 2.dp)
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    event.title,
                    style = Type.Body.copy(color = if (past) Palette.InkMuted else Palette.Ink, fontWeight = FontWeight.Medium),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (!past) PersonPills(event.persons, Modifier.padding(start = 12.dp))
            }
        }
    }
}

// --- Hoy se come (derecha, arriba) ---

/**
 * «Hoy se come»: todas las franjas del menú aceptado de hoy (N5), la actual en destacado y las pasadas atenuadas.
 * Sin plan aceptado no se pinta.
 */
@Composable
private fun MealsCard(state: UiState) {
    val view: MealsTodayView = MealsTodayState.of(state.meals, state.now, MEAL_ROWS) ?: return
    Card(Modifier.fillMaxWidth()) {
        CardHeader("Hoy se come", Icons.Outlined.Restaurant, Palette.Sage, count = view.rows.size + view.more)
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            view.rows.forEach { row ->
                val label = if (row.label.isEmpty()) "" else "${row.label} · "
                Text(
                    "${row.time}  $label${row.title}",
                    style = Type.Body.copy(
                        color = if (row.past) Palette.InkMuted else Palette.Ink,
                        fontWeight = if (row.current) FontWeight.SemiBold else FontWeight.Normal
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

// --- Próximos 3 días (derecha, medio) ---

/** Los eventos de mañana y de los dos días siguientes, con su día como cabecera (C2: sustituye al mes de puntos). */
@Composable
private fun UpcomingDaysCard(state: UiState, lastTouch: Long, modifier: Modifier) {
    val today = state.now.toLocalDate()
    val from = today.plusDays(1)
    val to = today.plusDays(UPCOMING_DAYS)
    val events = state.content?.events.orEmpty()
        .filter { !it.isOngoing(today) && it.at.toLocalDate() in from..to }
        .sortedBy { it.at }
    Card(modifier) {
        CardHeader("Próximos 3 días", Icons.Outlined.Event, Palette.Rain, count = events.size)
        if (events.isEmpty()) {
            EmptyState(Icons.Outlined.EventAvailable, Palette.Rain, "Nada los próximos días", "Sin eventos hasta dentro de 3 días", Modifier.weight(1f).fillMaxWidth())
            return@Card
        }
        UpcomingList(events, state.now, lastTouch) { event ->
            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    "${event.at.toLocalDate().shortLabel()} · ${event.at.format(HourMinute)}",
                    style = Type.Small.copy(color = Palette.InkSoft, fontWeight = FontWeight.SemiBold),
                    maxLines = 1,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(event.title, style = Type.Body, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    PersonPills(event.persons, Modifier.padding(start = 12.dp))
                }
            }
            Hairline()
        }
    }
}

// --- Rutinas de hoy (derecha, abajo) ---

/** Rutinas de hoy: la lista del día, con la siguiente sesión resaltada y las pasadas atenuadas. */
@Composable
private fun RoutinesCard(state: UiState, lastTouch: Long, modifier: Modifier) {
    val now = state.now
    val sessions = state.content?.sessions.orEmpty().filter { it.at.toLocalDate() == now.toLocalDate() }
    val upcoming = sessions.firstOrNull { !it.at.isBefore(now) }
    Card(modifier) {
        CardHeader("Rutinas de hoy", Icons.Outlined.Autorenew, Palette.Warm, count = sessions.count { !it.at.isBefore(now) })
        if (sessions.isEmpty()) {
            EmptyState(Icons.Outlined.Weekend, Palette.Warm, "Hoy no hay rutinas", "Día libre", Modifier.weight(1f).fillMaxWidth())
            return@Card
        }
        UpcomingList(sessions, now, lastTouch, Modifier.padding(top = 4.dp)) { session ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp).alpha(if (session.at.isBefore(now)) 0.5f else 1f)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(session.title, style = Type.Body, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(session.at.format(HourMinute), style = Type.Small.copy(color = if (session == upcoming) Palette.Accent else Palette.InkSoft))
                }
                PersonPills(session.persons)
            }
            Hairline()
        }
    }
}

/**
 * Lista con scroll que se abre con un solo elemento pasado a la vista, el último, y debajo los que faltan. Se recoloca
 * cuando pasa otro y, si se ha deslizado a mano, tras [SCROLL_RESET_MILLIS] sin tocar la pantalla ([lastTouch]).
 */
@Composable
private fun UpcomingList(items: List<Event>, now: LocalDateTime, lastTouch: Long, modifier: Modifier = Modifier, item: @Composable (Event) -> Unit) {
    val scroll = rememberScrollState()
    val past = items.count { it.at.isBefore(now) }
    var lastPastTop by remember { mutableIntStateOf(0) }
    val target = if (past > 0) lastPastTop else 0
    LaunchedEffect(past, target) { scroll.scrollTo(target) }
    LaunchedEffect(lastTouch, target) {
        delay(SCROLL_RESET_MILLIS)
        scroll.animateScrollTo(target)
    }
    Column(modifier.fadingScroll(scroll)) {
        items.forEachIndexed { i, entry ->
            Column(if (i == past - 1) Modifier.onPlaced { lastPastTop = it.positionInParent().y.roundToInt() } else Modifier) { item(entry) }
        }
    }
}

// --- Tareas (pantalla de tareas) ---

@Composable
fun TaskRow(task: Task, modifier: Modifier = Modifier) {
    // Sin casilla: el dashboard es de solo lectura y no se pueden marcar. A la derecha, las personas y la prioridad.
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier.fillMaxWidth().padding(vertical = 10.dp)) {
        Column(Modifier.weight(1f)) {
            Text(task.title, style = Type.Body, maxLines = 2, overflow = TextOverflow.Ellipsis)
            // Fecha límite (0041) en hora local, debajo del título.
            TaskDue.label(task.due_at)?.let { Text("Vence $it", style = Type.Small.copy(color = Palette.InkMuted)) }
        }
        PersonPills(task.persons, Modifier.padding(start = 12.dp))
        PriorityBadge(task.priorityValue, Modifier.padding(start = 16.dp))
    }
}

/** Color de cada prioridad: alta con el acento, media cálida y baja en salvia (la paleta de la app). */
fun priorityColor(priority: TaskPriority): Color = when (priority) {
    TaskPriority.ALTA -> Palette.Accent
    TaskPriority.MEDIA -> Palette.Warm
    TaskPriority.BAJA -> Palette.Sage
}

/** Píldora con la prioridad de la tarea, tintada con [priorityColor]. */
@Composable
fun PriorityBadge(priority: TaskPriority, modifier: Modifier = Modifier) {
    val color = priorityColor(priority)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier.background(color.copy(alpha = 0.14f), CircleShape).padding(horizontal = 14.dp, vertical = 5.dp)
    ) {
        Dot(color, 12)
        Text(priority.label, style = Type.Small.copy(color = Palette.Ink), maxLines = 1)
    }
}

/** Nombres en píldoras del color de cada persona. */
@Composable
fun PersonPills(persons: List<Person>?, modifier: Modifier = Modifier) {
    if (persons.isNullOrEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = modifier) {
        persons.forEach { person ->
            Text(
                person.name,
                style = Type.Small.copy(color = Color.White, fontWeight = FontWeight.SemiBold),
                maxLines = 1,
                modifier = Modifier.background(parseColor(person.color), RoundedCornerShape(14.dp)).padding(horizontal = 12.dp, vertical = 3.dp)
            )
        }
    }
}
