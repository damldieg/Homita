package com.lito.planify.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

// Planify "Glass" Tokens
val PrimaryColor = Color(0xFF3A1859) // Deep plum (today / accent)
val OnPrimaryColor = Color(0xFFFFFFFF)
val PrimaryContainerColor = Color(0xFFE7DCF0)
val OnPrimaryContainerColor = Color(0xFF240C3A)

// Soft neutral gradient used as app background
val BackgroundTopColor = Color(0xFFF4F3F1)
val BackgroundMidColor = Color(0xFFEDEBE8)
val BackgroundBottomColor = Color(0xFFE3E1DD)

val BackgroundColor = BackgroundTopColor
val SurfaceColor = Color(0xFFFBFAF8) // Sheets & dialogs
val SurfaceDimColor = Color(0xFFEEECE9)

val OnSurfaceColor = Color(0xFF16151A)
val OnSurfaceVariantColor = Color(0xFF5E5C60)

val OutlineColor = Color(0xFFCBC8C3)
val OutlineDimColor = Color(0x14000000)

val ErrorColor = Color(0xFFB3261E)

// Glass surfaces
val GlassColor = Color.White.copy(alpha = 0.72f)
val GlassStrongColor = Color.White.copy(alpha = 0.9f)
val GlassBorderColor = Color.White
val PillFillColor = Color.Black.copy(alpha = 0.06f)

// Day pills
val TodayPillColor = Color(0xFFE5484D)
val TomorrowPillColor = Color(0xFFEF8F3A)

val BackgroundBrush = Brush.verticalGradient(listOf(BackgroundTopColor, BackgroundMidColor, BackgroundBottomColor))

private val LightColorScheme = lightColorScheme(
    primary = PrimaryColor,
    onPrimary = OnPrimaryColor,
    primaryContainer = PrimaryContainerColor,
    onPrimaryContainer = OnPrimaryContainerColor,
    background = BackgroundColor,
    onBackground = OnSurfaceColor,
    surface = SurfaceColor,
    onSurface = OnSurfaceColor,
    surfaceVariant = SurfaceDimColor,
    onSurfaceVariant = OnSurfaceVariantColor,
    surfaceTint = Color.Transparent,
    surfaceContainerLow = SurfaceColor,
    surfaceContainer = SurfaceColor,
    surfaceContainerHigh = SurfaceColor,
    outline = OutlineColor,
    outlineVariant = OutlineDimColor,
    error = ErrorColor
)

@Composable
fun PlanifyTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = LightColorScheme,
        typography = AppTypography,
        content = content
    )
}
