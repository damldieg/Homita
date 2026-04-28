package com.lito.planify.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Planify High-Fidelity Tokens
val PrimaryColor = Color(0xFF4B4D99) // oklch(0.55 0.15 255)
val OnPrimaryColor = Color(0xFFFFFFFF)
val PrimaryContainerColor = Color(0xFFE6E6F7)
val OnPrimaryContainerColor = Color(0xFF1A1A3A)

val BackgroundColor = Color(0xFFF7F5F2)
val SurfaceColor = Color(0xFFFFFFFF)
val SurfaceDimColor = Color(0xFFEEEBE5)

val OnSurfaceColor = Color(0xFF1A1916)
val OnSurfaceVariantColor = Color(0xFF5A5853)

val OutlineColor = Color(0xFFC8C5BD)
val OutlineDimColor = Color(0xFFE5E2DB)

val ErrorColor = Color(0xFFB3261E)

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
