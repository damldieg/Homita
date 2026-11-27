package com.dld.homita.dashboard.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Thermostat
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.Freshness
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.delay

/** Pantallas de la barra: Hoy, Calendario, Tiempo, Tareas y Ajustes; el tiempo también se abre desde su tarjeta de Hoy. */
enum class Page(val label: String, val icon: ImageVector) {
    Today("Hoy", Icons.Outlined.Home),
    Calendar("Calendario", Icons.Outlined.CalendarMonth),
    Weather("Tiempo", Icons.Outlined.Thermostat),
    Tasks("Tareas", Icons.Outlined.Checklist),
    Settings("Ajustes", Icons.Outlined.Settings)
}

/** Acciones que dependen de la actividad (pantalla, quiosco, ajustes de Android). */
class DashboardActions(
    val sleep: () -> Unit,
    val openWifi: () -> Unit,
    val openSettings: () -> Unit,
    val powerMenu: () -> Unit,
)

private const val IDLE_MILLIS = 120_000L

/** Solape entre las líneas del reloj lateral: deja la distancia entre las cifras en el interlineado (52). */
private val RAIL_CLOCK_OVERLAP = (-30).dp

/**
 * Panel con la animación de marca encima: arranque sin sesión (First), login recién hecho (Login) o arranque
 * con sesión (Returning). Se retira sola al terminar.
 */
@Composable
fun DashboardApp(
    state: UiState,
    actions: DashboardActions,
    onLogin: (String, String) -> Unit,
    onLoadWeek: (LocalDate) -> Unit,
    settings: SettingsCallbacks,
    onPeek: () -> Unit,
    onDismissDue: (String) -> Unit
) {
    var intro by remember { mutableStateOf<IntroStyle?>(if (state.token == null) IntroStyle.First else IntroStyle.Returning) }
    var hadToken by remember { mutableStateOf(state.token != null) }
    // Sin token → con token = login recién hecho (no se dispara en el arranque ni al renovar datos).
    LaunchedEffect(state.token != null) {
        val has = state.token != null
        if (!hadToken && has) intro = IntroStyle.Login
        hadToken = has
    }
    Box(Modifier.fillMaxSize()) {
        DashboardContent(state, actions, onLogin, onLoadWeek, settings, onPeek, onDismissDue)
        intro?.let { BrandIntro(it) { intro = null } }
    }
}

@Composable
private fun DashboardContent(
    state: UiState,
    actions: DashboardActions,
    onLogin: (String, String) -> Unit,
    onLoadWeek: (LocalDate) -> Unit,
    settings: SettingsCallbacks,
    onPeek: () -> Unit,
    onDismissDue: (String) -> Unit
) {
    var page by remember { mutableStateOf(Page.Today) }
    var lastTouch by remember { mutableLongStateOf(0L) }

    // Tras 2 minutos sin tocar se vuelve a Hoy.
    LaunchedEffect(page, lastTouch) {
        if (page == Page.Today) return@LaunchedEffect
        delay(IDLE_MILLIS)
        page = Page.Today
    }
    // Es el launcher: "atrás" vuelve a Hoy y nunca cierra la actividad.
    BackHandler { page = Page.Today }

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.Background)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent(PointerEventPass.Initial)
                        lastTouch = System.currentTimeMillis()
                    }
                }
            }
    ) {
        if (state.token == null) {
            LoginScreen(state, onLogin, actions.openWifi)
            return@Box
        }
        if (state.night) {
            NightScreen(state, onWake = {
                page = Page.Today
                onPeek()
            })
            return@Box
        }
        Row(Modifier.fillMaxSize()) {
            Rail(page, state, onSelect = { page = it }, onSleep = actions.sleep)
            Box(Modifier.weight(1f).fillMaxHeight()) {
                when (page) {
                    Page.Today -> TodayScreen(state, lastTouch, onOpenWeather = { page = Page.Weather }, onDismissDue = onDismissDue)
                    Page.Calendar -> CalendarScreen(state, onLoadWeek)
                    Page.Weather -> WeatherScreen(state)
                    Page.Tasks -> TasksScreen(state)
                    Page.Settings -> SettingsScreen(state, actions, settings)
                }
            }
        }
    }
}

@Composable
private fun Rail(current: Page, state: UiState, onSelect: (Page) -> Unit, onSleep: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(136.dp)
            .fillMaxHeight()
            .background(Palette.Rail)
            .padding(vertical = 32.dp)
    ) {
        // Las pantallas arriba, con su nombre bajo el icono (U6); el apagado, con su nombre
        Column(verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            listOf(Page.Today, Page.Calendar, Page.Weather, Page.Tasks, Page.Settings).forEach { page ->
                RailItem(page.label, page.icon, page == current) { onSelect(page) }
            }
            RailItem("Apagar", Icons.Outlined.Bedtime, false, onClick = onSleep)
        }
        Spacer(Modifier.weight(1f))
        // El reloj de la barra no se repite en Hoy (que ya tiene el suyo); el estado de los datos, siempre
        if (current != Page.Today) RailClock(state)
        RailStatus(state, Modifier.padding(top = 12.dp))
    }
}

/** Botón de la barra: el icono y su nombre debajo, en 24 px. */
@Composable
private fun RailItem(label: String, icon: ImageVector, selected: Boolean, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .width(128.dp)
            .background(if (selected) Palette.Card else Palette.Rail, RoundedCornerShape(30.dp))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
            .padding(vertical = 14.dp)
    ) {
        Icon(icon, contentDescription = label, tint = if (selected) Palette.Ink else Palette.InkMuted, modifier = Modifier.size(52.dp))
        Text(label, style = Type.Small.copy(color = if (selected) Palette.Ink else Palette.InkMuted, fontWeight = FontWeight.Medium, letterSpacing = 0.sp), maxLines = 1, softWrap = false)
    }
}

/** La hora, con horas y minutos en dos líneas. */
@Composable
private fun RailClock(state: UiState) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        // Horas y minutos en dos líneas con las mismas métricas, cifras tabulares e interlineado ajustado a la
        // altura de las cifras para que queden juntas. Las cifras que cambian se deslizan (RollingText).
        val hour = if (state.clockValid) "%02d".format(state.now.hour) else "--"
        val minute = if (state.clockValid) "%02d".format(state.now.minute) else "--"
        val style = Type.Title.copy(
            fontSize = 64.sp,
            lineHeight = 52.sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = (-2).sp,
            fontFeatureSettings = "tnum",
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both)
        )
        // Cada línea es su propio texto (para animar sus cifras): se solapan para dejar el mismo interlineado de 52.
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(RAIL_CLOCK_OVERLAP)) {
            RollingText(hour, style)
            RollingText(minute, style.copy(color = Palette.InkSoft))
        }
    }
}

/**
 * Estado de los datos (U7): «Sin conexión» y/o «Actualizado hace 2 h» cuando la copia tiene más de 15 min. Texto de 24 px.
 */
@Composable
private fun RailStatus(state: UiState, modifier: Modifier = Modifier) {
    // Con la hora sin sincronizar (RTC de fábrica) no se puede medir la edad de la copia: solo el estado de la red.
    val nowMillis = if (state.clockValid) state.now.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() else null
    val text = Freshness.label(if (nowMillis != null) state.contentFetchedAt else null, nowMillis ?: 0L, state.online, state.connected) ?: return
    Text(
        text,
        style = Type.Small.copy(color = if (!state.online || !state.connected) Palette.Danger else Palette.InkSoft),
        textAlign = TextAlign.Center,
        modifier = modifier.width(120.dp)
    )
}

/** Botón en píldora. */
@Composable
fun PillButton(
    text: String,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    enabled: Boolean = true,
    background: Color = Palette.Card,
    onClick: () -> Unit
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(84.dp)
            // Recortado a su forma, para que el efecto al pulsar no salga cuadrado
            .clip(RoundedCornerShape(42.dp))
            .background(
                when {
                    !enabled -> Palette.Line
                    primary -> Palette.Ink
                    else -> background
                },
                RoundedCornerShape(42.dp)
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 40.dp)
    ) {
        Text(text, style = Type.Body.copy(color = if (primary) Palette.Card else Palette.Ink), maxLines = 1)
    }
}

@Composable
fun ScreenPadding(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().padding(start = 64.dp, end = 64.dp, top = 60.dp, bottom = 52.dp)) { content() }
}
