package com.lito.planify.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.ui.theme.GlassColor
import com.lito.planify.ui.theme.OnSurfaceColor
import com.lito.planify.ui.theme.OnSurfaceVariantColor

/** Separador fino entre filas de una misma tarjeta de cristal. */
@Composable
private fun GroupDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier = modifier.padding(horizontal = 18.dp), thickness = 1.dp, color = com.lito.planify.ui.theme.OutlineDimColor)
}

/**
 * Fila uniforme para Listas y Calendarios (Barra de color + Texto + Badge + Flecha).
 */
@Composable
fun PlanifyRowItem(
    title: String,
    count: Int,
    colorHex: String,
    index: Int = 0,
    groupCount: Int = 1,
    onClick: () -> Unit
) {
    val color = parseHexColor(colorHex)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassGroupRow(index, groupCount)
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().height(72.dp).padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(
                modifier = Modifier
                    .width(5.dp)
                    .height(32.dp)
                    .background(color, CircleShape)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium.copy(fontSize = 18.sp),
                color = OnSurfaceColor,
                modifier = Modifier.weight(1f)
            )
            if (count >= 0) {
                Text(
                    text = count.toString(),
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
                    color = OnSurfaceColor,
                    modifier = Modifier
                        .background(com.lito.planify.ui.theme.PillFillColor, CircleShape)
                        .padding(horizontal = 11.dp, vertical = 5.dp)
                )
            }
            Icon(Icons.Default.ChevronRight, null, tint = OnSurfaceVariantColor, modifier = Modifier.size(20.dp))
        }
        if (index < groupCount - 1) GroupDivider()
    }
}

/**
 * Casilla cuadrada redondeada en el color de la lista.
 */
@Composable
fun PlanifyCheckBox(isChecked: Boolean, color: Color, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(7.dp)
    Box(
        modifier = modifier
            .size(24.dp)
            .then(
                if (isChecked) Modifier.background(color, shape)
                else Modifier.border(2.2.dp, color, shape)
            ),
        contentAlignment = Alignment.Center
    ) {
        if (isChecked) {
            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
        }
    }
}

/**
 * Fila uniforme para Tareas.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun PlanifyTaskRow(
    title: String,
    info: String? = null, // Lista a la que pertenece (vista global)
    colorHex: String?,
    isChecked: Boolean = false,
    isToggling: Boolean = false,
    onToggle: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
    index: Int = 0,
    groupCount: Int = 1,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit
) {
    val color = parseHexColor(colorHex)

    val clickModifier = if (onLongClick != null) {
        Modifier.combinedClickable(
            enabled = !isToggling,
            onClick = { if (onToggle != null) onToggle() else onClick() },
            onLongClick = onLongClick
        )
    } else {
        Modifier.clickable(enabled = !isToggling) { if (onToggle != null) onToggle() else onClick() }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .glassGroupRow(index, groupCount)
            .then(clickModifier)
            .alpha(if (isToggling) 0.5f else 1f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (onToggle != null) {
                PlanifyCheckBox(isChecked = isChecked, color = color)
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 16.sp,
                        fontWeight = if (isChecked) FontWeight.Medium else FontWeight.SemiBold,
                        textDecoration = if (isChecked) TextDecoration.LineThrough else TextDecoration.None
                    ),
                    color = if (isChecked) OnSurfaceVariantColor else OnSurfaceColor
                )
                if (info != null) {
                    Text(
                        text = info,
                        style = MaterialTheme.typography.bodySmall,
                        color = OnSurfaceVariantColor
                    )
                }
            }

            if (onDelete != null) {
                IconButton(
                    onClick = { onDelete() },
                    modifier = Modifier.size(28.dp)
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Borrar",
                        tint = OnSurfaceColor.copy(alpha = 0.3f),
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
        }
        if (index < groupCount - 1) GroupDivider()
    }
}

/**
 * Fila uniforme para Eventos (estilo agenda: barra fina de color, título en negrita y hora con reloj).
 */
@Composable
fun PlanifyEventRow(
    title: String,
    time: String,
    subtitle: String? = null,
    relativeTime: String? = null,
    colorHex: String?,
    hasAlarm: Boolean = false,
    isPast: Boolean = false,
    index: Int = 0,
    groupCount: Int = 1,
    onClick: () -> Unit
) {
    val color = parseHexColor(colorHex)
    val secondary = OnSurfaceVariantColor

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassGroupRow(index, groupCount)
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(IntrinsicSize.Min)
                .padding(horizontal = 18.dp, vertical = 14.dp)
                .alpha(if (isPast) 0.55f else 1f),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .width(4.dp)
                    .fillMaxHeight()
                    .background(color, CircleShape)
            )
            Column(
                modifier = Modifier.padding(start = 14.dp).weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = OnSurfaceColor
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Schedule, null, tint = secondary, modifier = Modifier.size(14.dp))
                    Text(
                        text = if (subtitle != null) "$time  ·  $subtitle" else time,
                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                        color = secondary,
                        modifier = Modifier.padding(start = 5.dp)
                    )
                    if (hasAlarm) {
                        Icon(
                            Icons.Default.Notifications,
                            contentDescription = "Alarma",
                            tint = secondary,
                            modifier = Modifier.padding(start = 6.dp).size(13.dp)
                        )
                    }
                }
            }
            if (relativeTime != null) {
                Text(
                    text = relativeTime.uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    color = OnSurfaceColor,
                    modifier = Modifier
                        .padding(start = 8.dp)
                        .background(com.lito.planify.ui.theme.PillFillColor, CircleShape)
                        .padding(horizontal = 9.dp, vertical = 4.dp)
                )
            }
        }
        if (index < groupCount - 1) GroupDivider()
    }
}

@Composable
fun PlanifyDashedCard(
    text: String,
    onClick: () -> Unit
) {
    val shape = RoundedCornerShape(22.dp)
    Box(
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 20.dp)
            .fillMaxWidth()
            .height(64.dp)
            .clip(shape)
            .background(GlassColor.copy(alpha = 0.35f), shape)
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.matchParentSize()) {
            drawRoundRect(
                color = com.lito.planify.ui.theme.OutlineColor,
                style = Stroke(width = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f), 0f)),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(22.dp.toPx())
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Add, null, tint = OnSurfaceColor, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                text = text,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold),
                color = OnSurfaceColor
            )
        }
    }
}
