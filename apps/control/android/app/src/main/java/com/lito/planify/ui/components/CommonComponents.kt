package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.ui.theme.GlassBorderColor
import com.lito.planify.ui.theme.GlassColor
import com.lito.planify.ui.theme.OnSurfaceColor
import com.lito.planify.ui.theme.OnSurfaceVariantColor

@Composable
fun PlanifyFilterChip(
    label: String,
    isSelected: Boolean,
    colorHex: String? = null,
    onClick: () -> Unit
) {
    val dotColor = try { colorHex?.let { Color(android.graphics.Color.parseColor(it)) } } catch (e: Exception) { null }

    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = if (isSelected) OnSurfaceColor else GlassColor,
        border = if (!isSelected) androidx.compose.foundation.BorderStroke(1.dp, GlassBorderColor) else null,
        modifier = Modifier.height(36.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            if (dotColor != null) {
                Box(
                    modifier = Modifier
                        .padding(end = 8.dp)
                        .size(8.dp)
                        .background(dotColor, CircleShape)
                )
            }
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp
                ),
                color = if (isSelected) Color.White else OnSurfaceVariantColor
            )
        }
    }
}

@Composable
fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 0.8.sp),
        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 8.dp)
    )
}
