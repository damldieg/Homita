package com.lito.planify.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.R
import com.lito.planify.ui.theme.*
import com.lito.planify.util.DateTimeUtils
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale

/** Fondo degradado neutro común a toda la app. */
@Composable
fun PlanifyBackground(content: @Composable BoxScope.() -> Unit) {
    Box(modifier = Modifier.fillMaxSize().background(BackgroundBrush), content = content)
}

/** Superficie translúcida tipo "cristal esmerilado". */
fun Modifier.glass(shape: Shape = RoundedCornerShape(24.dp), strong: Boolean = false): Modifier =
    this
        .clip(shape)
        .background(if (strong) GlassStrongColor else GlassColor, shape)
        .border(1.dp, GlassBorderColor, shape)

/** Forma para filas agrupadas dentro de una misma tarjeta de cristal. */
fun groupShape(index: Int, count: Int, radius: Dp = 22.dp): Shape = when {
    count == 1 -> RoundedCornerShape(radius)
    index == 0 -> RoundedCornerShape(topStart = radius, topEnd = radius)
    index == count - 1 -> RoundedCornerShape(bottomStart = radius, bottomEnd = radius)
    else -> RoundedCornerShape(0.dp)
}

/** Fondo de fila agrupada (sin bordes internos, para que el grupo se lea como una sola tarjeta). */
fun Modifier.glassGroupRow(index: Int, count: Int): Modifier =
    this
        .padding(horizontal = 16.dp)
        .clip(groupShape(index, count))
        .background(GlassColor, groupShape(index, count))

/** Idioma actual leído de forma observable (se recompone si cambia la configuración). */
@Composable
@ReadOnlyComposable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

fun parseHexColor(hex: String?, fallback: Color = PrimaryColor): Color =
    try { hex?.let { Color(android.graphics.Color.parseColor(it)) } ?: fallback } catch (e: Exception) { fallback }

/** Selector segmentado en píldora que sustituye a las pestañas clásicas. [onSheet] lo adapta al fondo de las hojas. */
@Composable
fun GlassTabs(
    titles: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onSheet: Boolean = false
) {
    Row(
        modifier = modifier
            .then(if (onSheet) Modifier.background(PillFillColor, CircleShape) else Modifier.glass(CircleShape))
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        titles.forEachIndexed { index, title ->
            val selected = index == selectedIndex
            val bg by animateColorAsState(if (selected) OnSurfaceColor else Color.Transparent, label = "tabBg")
            val fg by animateColorAsState(if (selected) Color.White else OnSurfaceVariantColor, label = "tabFg")
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(40.dp)
                    .clip(CircleShape)
                    .background(bg, CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) { onSelect(index) },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold, fontSize = 15.sp),
                    color = fg
                )
            }
        }
    }
}

/** Píldora de día: "Hoy" (rojo), "Mañana" (naranja) o neutra. */
@Composable
fun DayPill(date: LocalDate, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val today = LocalDate.now()
    val (bg, fg) = when (date) {
        today -> TodayPillColor to Color.White
        today.plusDays(1) -> TomorrowPillColor to Color.White
        else -> OnSurfaceColor.copy(alpha = 0.82f) to Color.White
    }
    Text(
        text = DateTimeUtils.dayLabel(context, date),
        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp, letterSpacing = 0.2.sp),
        color = fg,
        modifier = modifier
            .background(bg, CircleShape)
            .padding(horizontal = 12.dp, vertical = 4.dp)
    )
}

/** Etiqueta de sección (PENDIENTES · 4) sobre el fondo arena. */
@Composable
fun GlassSectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge.copy(fontSize = 12.sp, letterSpacing = 1.2.sp),
        color = OnSurfaceVariantColor,
        modifier = modifier.padding(start = 28.dp, end = 28.dp, top = 22.dp, bottom = 10.dp)
    )
}

/** Cabecera de sección destacada: icono, título, contador y línea divisoria (p. ej. "Pasados"). */
@Composable
fun GlassSectionHeader(icon: ImageVector, title: String, count: Int, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(34.dp).glass(CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = OnSurfaceVariantColor, modifier = Modifier.size(18.dp))
        }
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = OnSurfaceColor,
            modifier = Modifier.padding(start = 10.dp)
        )
        Text(
            text = count.toString(),
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
            color = OnSurfaceVariantColor,
            modifier = Modifier
                .padding(start = 8.dp)
                .background(PillFillColor, CircleShape)
                .padding(horizontal = 9.dp, vertical = 3.dp)
        )
        HorizontalDivider(
            modifier = Modifier.weight(1f).padding(start = 12.dp),
            thickness = 1.dp,
            color = OutlineColor.copy(alpha = 0.6f)
        )
    }
}

/**
 * Mini calendario mensual con puntos de color por evento,
 * inspirado en los widgets de pantalla de bloqueo.
 */
@Composable
fun MonthCalendarCard(
    eventColorsByDate: Map<LocalDate, List<Color>>,
    modifier: Modifier = Modifier,
    onDayClick: ((LocalDate) -> Unit)? = null
) {
    val locale = currentLocale()
    val today = LocalDate.now()
    val month = YearMonth.from(today)
    val firstDayOfWeek = WeekFields.of(locale).firstDayOfWeek
    val leadingBlanks = (month.atDay(1).dayOfWeek.value - firstDayOfWeek.value + 7) % 7
    val cells = List(leadingBlanks) { null } + (1..month.lengthOfMonth()).map { month.atDay(it) }
    val weekdays = (0..6).map { firstDayOfWeek.plus(it.toLong()).getDisplayName(TextStyle.NARROW, locale) }

    Column(
        modifier = modifier
            .glass(RoundedCornerShape(28.dp))
            .padding(horizontal = 18.dp, vertical = 16.dp)
    ) {
        Text(
            text = month.month.getDisplayName(TextStyle.FULL_STANDALONE, locale).replaceFirstChar { it.uppercaseChar() },
            style = MaterialTheme.typography.titleLarge,
            color = OnSurfaceColor,
            modifier = Modifier.padding(bottom = 10.dp)
        )
        Row(modifier = Modifier.fillMaxWidth()) {
            weekdays.forEach {
                Text(
                    text = it.uppercase(locale),
                    style = MaterialTheme.typography.labelMedium,
                    color = OnSurfaceColor,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        cells.chunked(7).forEach { week ->
            Row(modifier = Modifier.fillMaxWidth()) {
                (0 until 7).forEach { i ->
                    val date = week.getOrNull(i)
                    Box(modifier = Modifier.weight(1f).height(36.dp), contentAlignment = Alignment.TopCenter) {
                        if (date != null) {
                            MonthDayCell(
                                date = date,
                                isToday = date == today,
                                dots = eventColorsByDate[date].orEmpty(),
                                onClick = onDayClick?.takeIf { eventColorsByDate.containsKey(date) }
                            )
                        }
                    }
                }
            }
        }

    }
}

@Composable
private fun MonthDayCell(
    date: LocalDate,
    isToday: Boolean,
    dots: List<Color>,
    onClick: ((LocalDate) -> Unit)?
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .then(if (onClick != null) Modifier.clickable { onClick(date) } else Modifier)
            .padding(horizontal = 4.dp)
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(if (isToday) PrimaryColor else Color.Transparent, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = date.dayOfMonth.toString(),
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = if (isToday) FontWeight.Bold else FontWeight.Medium,
                    fontSize = 14.sp
                ),
                color = if (isToday) Color.White else OnSurfaceColor
            )
        }
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier.height(6.dp).padding(top = 2.dp)
        ) {
            dots.distinct().take(3).forEach { c ->
                Box(Modifier.size(4.dp).background(c, CircleShape))
            }
        }
    }
}
