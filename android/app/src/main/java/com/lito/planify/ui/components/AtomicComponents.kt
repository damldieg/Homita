package com.lito.planify.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.ui.theme.PrimaryColor
import com.lito.planify.ui.theme.PrimaryContainerColor

@Composable
fun PlanifyLogo(size: Dp = 120.dp) {
    Canvas(modifier = Modifier.size(size)) {
        val scale = size.toPx() / 120f
        
        // The SVG has a rect at x=8, y=8, width=104, height=104, rx=28
        val rectSize = 104f * scale
        val rectOffset = 8f * scale
        val cornerRadius = 28f * scale
        
        // Approximate colors for oklch(0.60 0.15 255) to oklch(0.50 0.15 280)
        val gradient = Brush.linearGradient(
            colors = listOf(Color(0xFF4A7DDF), Color(0xFF4749AD)),
            start = Offset(rectOffset, rectOffset),
            end = Offset(rectOffset + rectSize, rectOffset + rectSize)
        )
        
        drawRoundRect(
            brush = gradient,
            topLeft = Offset(rectOffset, rectOffset),
            size = Size(rectSize, rectSize),
            cornerRadius = CornerRadius(cornerRadius, cornerRadius)
        )
        
        val dotRadius = 4f * scale
        drawCircle(Color.White.copy(alpha = 0.4f), dotRadius, Offset(36f * scale, 36f * scale))
        drawCircle(Color.White.copy(alpha = 0.55f), dotRadius, Offset(60f * scale, 36f * scale))
        drawCircle(Color.White.copy(alpha = 0.4f), dotRadius, Offset(84f * scale, 36f * scale))
        drawCircle(Color.White.copy(alpha = 0.55f), dotRadius, Offset(36f * scale, 60f * scale))
        
        val path = Path().apply {
            moveTo(40f * scale, 68f * scale)
            lineTo(56f * scale, 84f * scale)
            lineTo(92f * scale, 46f * scale)
        }
        drawPath(
            path = path,
            color = Color.White,
            style = Stroke(width = 8f * scale, cap = StrokeCap.Round, join = StrokeJoin.Round)
        )
    }
}

@Composable
fun CustomTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    singleLine: Boolean = true,
    enabled: Boolean = true,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions(capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences),
    keyboardActions: KeyboardActions = KeyboardActions.Default
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = if (label.isNotEmpty()) { { Text(label.uppercase(), style = MaterialTheme.typography.labelLarge) } } else null,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        leadingIcon = leadingIcon,
        trailingIcon = trailingIcon,
        visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        singleLine = singleLine,
        enabled = enabled,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = MaterialTheme.colorScheme.primary,
            unfocusedBorderColor = MaterialTheme.colorScheme.outline,
            focusedLabelColor = MaterialTheme.colorScheme.primary,
            unfocusedLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
            focusedContainerColor = Color.White,
            unfocusedContainerColor = Color.White
        )
    )
}

@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false,
    icon: @Composable (() -> Unit)? = null
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(56.dp),
        enabled = enabled && !isLoading,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        ),
        contentPadding = PaddingValues(horizontal = 24.dp)
    ) {
        if (isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(24.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) {
                    icon()
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(text = text, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun TonalButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isDestructive: Boolean = false,
    icon: @Composable (() -> Unit)? = null
) {
    val containerColor = if (isDestructive) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.primaryContainer
    val contentColor = if (isDestructive) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer

    Button(
        onClick = onClick,
        modifier = modifier.height(56.dp),
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = containerColor,
            contentColor = contentColor
        ),
        contentPadding = PaddingValues(horizontal = 24.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                icon()
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(text = text, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun OutlinedActionButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: @Composable (() -> Unit)? = null
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.height(56.dp),
        enabled = enabled,
        shape = CircleShape,
        border = androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.outline),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.primary
        ),
        contentPadding = PaddingValues(horizontal = 24.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                icon()
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(text = text, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun HueColorPicker(
    currentColorHex: String,
    onColorChange: (String) -> Unit
) {
    val initialColor = try { android.graphics.Color.parseColor(currentColorHex) } catch (e: Exception) { android.graphics.Color.parseColor("#B97A7A") }
    val hsv = FloatArray(3)
    android.graphics.Color.colorToHSV(initialColor, hsv)
    var hue by remember { mutableStateOf(hsv[0]) }

    // Muted palette for the slider background
    val mutedBrush = Brush.linearGradient(
        colors = listOf(
            Color(0xFFB97A7A), // Muted Red
            Color(0xFFB9997A), // Ochre/Tan
            Color(0xFF99B97A), // Sage/Olive
            Color(0xFF7AB999), // Muted Mint
            // Color(0xFF7A99B9), // Muted Blue
            Color(0xFF7A7AB9), // Muted Indigo
            Color(0xFF997AB9), // Muted Purple
            Color(0xFFB97A99)  // Muted Rose
        )
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(32.dp)
            .background(mutedBrush, CircleShape)
            .padding(horizontal = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Slider(
            value = hue,
            onValueChange = { 
                hue = it 
                // Using S=0.6, V=0.75 for earthy/muted tones
                val colorInt = android.graphics.Color.HSVToColor(floatArrayOf(it, 0.6f, 0.75f))
                val hex = String.format("#%06X", 0xFFFFFF and colorInt)
                onColorChange(hex)
            },
            valueRange = 0f..360f,
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color.Transparent,
                inactiveTrackColor = Color.Transparent
            )
        )
    }
}
