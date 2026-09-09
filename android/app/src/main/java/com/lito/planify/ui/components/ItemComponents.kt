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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Notifications
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
import com.lito.planify.ui.theme.OutlineDimColor

/**
 * Fila uniforme para Listas y Calendarios (Punto + Texto + Badge + Flecha).
 */
@Composable
fun PlanifyRowItem(
    title: String,
    count: Int,
    colorHex: String,
    onClick: () -> Unit
) {
    val color = try { Color(android.graphics.Color.parseColor(colorHex)) } catch (e: Exception) { Color(0xFF4B4D99) }
    
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(72.dp)
            .background(Color.White)
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Thick color bar on the left
            Box(
                modifier = Modifier
                    .width(8.dp)
                    .fillMaxHeight()
                    .background(color)
            )
            
            Row(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 18.sp,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.SansSerif
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f)
                )

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (count >= 0) {
                        Surface(
                            shape = CircleShape,
                            color = Color(0xFFF0F0F0),
                            modifier = Modifier.size(32.dp)
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Text(
                                    text = count.toString(),
                                    style = MaterialTheme.typography.labelLarge.copy(
                                        fontWeight = FontWeight.Bold, 
                                        fontSize = 12.sp
                                    ),
                                    color = Color(0xFF9E9E9E)
                                )
                            }
                        }
                    }
                    Icon(
                        Icons.Default.ChevronRight, 
                        null, 
                        tint = Color(0xFFBDBDBD), 
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }
        HorizontalDivider(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(start = 8.dp),
            thickness = 0.5.dp, 
            color = OutlineDimColor
        )
    }
}

/**
 * Fila uniforme para Tareas y Eventos.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun PlanifyTaskRow(
    title: String,
    info: String? = null, // Fecha u hora
    colorHex: String?,
    isChecked: Boolean = false,
    isToggling: Boolean = false,
    onToggle: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
    showLeftColorBar: Boolean = false,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit
) {
    val color = try { Color(android.graphics.Color.parseColor(colorHex ?: "#4B4D99")) } catch(e: Exception) { Color(0xFF4B4D99) }

    val rowModifier = if (onLongClick != null) {
        modifier
            .fillMaxWidth()
            .alpha(if (isToggling) 0.5f else 1f)
            .background(Color.White)
            .combinedClickable(
                enabled = !isToggling,
                onClick = { if (onToggle != null) onToggle() else onClick() },
                onLongClick = onLongClick
            )
    } else {
        modifier
            .fillMaxWidth()
            .alpha(if (isToggling) 0.5f else 1f)
            .background(Color.White)
            .clickable(enabled = !isToggling) { if(onToggle != null) onToggle() else onClick() }
    }

    Box(
        modifier = rowModifier
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (showLeftColorBar) {
                Box(modifier = Modifier.width(6.dp).fillMaxHeight().background(color))
            }
            
            Row(
                modifier = Modifier.padding(horizontal = if (showLeftColorBar) 14.dp else 20.dp, vertical = 20.dp).fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
            // Checkbox area
            if (onToggle != null) {
                if (isChecked) {
                    Box(
                        modifier = Modifier.size(24.dp).background(color, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(androidx.compose.material.icons.Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
                    }
                } else {
                    Box(
                        modifier = Modifier.size(24.dp).border(width = 2.dp, color = Color(0xFFC8C5BD), shape = CircleShape)
                    )
                }
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Normal,
                        textDecoration = if (isChecked) TextDecoration.LineThrough else TextDecoration.None
                    ),
                    color = if (isChecked) Color(0xFF757575) else MaterialTheme.colorScheme.onSurface
                )
                if (info != null) {
                    Text(text = info, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            if (onDelete != null) {
                IconButton(
                    onClick = { onDelete() },
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        androidx.compose.material.icons.Icons.Default.Delete,
                        contentDescription = "Borrar",
                        tint = Color.Black.copy(alpha = 0.15f),
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
            } // Close the inner Row
        } // Close the outer Row
        HorizontalDivider(modifier = Modifier.align(Alignment.BottomEnd), thickness = 0.5.dp, color = OutlineDimColor)
    }
}

/**
 * Fila uniforme para Eventos.
 */
@Composable
fun PlanifyEventRow(
    title: String,
    dateInfo: String,
    relativeTime: String? = null,
    colorHex: String?,
    hasAlarm: Boolean = false,
    onClick: () -> Unit
) {
    val color = try { Color(android.graphics.Color.parseColor(colorHex ?: "#4B4D99")) } catch(e: Exception) { Color(0xFF4B4D99) }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White)
            .clickable { onClick() }
    ) {
        Row(modifier = Modifier.height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically) {
            // Borde grueso a la izquierda
            Box(modifier = Modifier.width(6.dp).fillMaxHeight().background(color))
            
            Column(
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 20.dp).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = dateInfo.uppercase(),
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 0.5.sp
                            ),
                            color = Color(0xFF757575)
                        )
                        if (hasAlarm) {
                            Icon(
                                androidx.compose.material.icons.Icons.Default.Notifications,
                                contentDescription = "Alarma",
                                tint = Color(0xFF757575),
                                modifier = Modifier.padding(start = 6.dp).size(14.dp)
                            )
                        }
                    }
                    
                    if (relativeTime != null) {
                        Surface(
                            color = Color(0xFFE0E0E0),
                            shape = RoundedCornerShape(4.dp)
                        ) {
                            Text(
                                text = relativeTime.uppercase(),
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 10.sp
                                ),
                                color = Color(0xFF757575),
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                }

                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Serif,
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
        HorizontalDivider(modifier = Modifier.align(Alignment.BottomEnd), thickness = 0.5.dp, color = OutlineDimColor)
    }
}
@Composable
fun PlanifyDashedCard(
    text: String,
    onClick: () -> Unit
) {
    val outlineColor = Color(0xFFE0E0E0)
    Box(
        modifier = Modifier
            .padding(horizontal = 20.dp, vertical = 24.dp)
            .fillMaxWidth()
            .height(72.dp)
            .background(Color.White, RoundedCornerShape(16.dp))
            .clip(RoundedCornerShape(16.dp))
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.matchParentSize()) {
            drawRoundRect(
                color = outlineColor,
                style = Stroke(width = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(16.dp.toPx())
            )
        }
        Text(
            text = text, 
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium), 
            color = Color(0xFF757575)
        )
    }
}
