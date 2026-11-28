package com.dld.homita.dashboard.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.createBitmap
import com.dld.homita.dashboard.R
import com.dld.homita.dashboard.ui.theme.GeistMono
import kotlin.math.ceil
import kotlinx.coroutines.withContext

/**
 * Reloj de paletas (split-flap), como los paneles de los aeropuertos: cada cifra en una placa oscura partida por la
 * mitad (sin ranura). Al cambiar, la mitad de arriba cae y descubre la cifra nueva. Solo se anima el minuto que cambia.
 */
@Composable
fun FlipClock(text: String, modifier: Modifier = Modifier, tile: Dp = 110.dp, height: Dp = 184.dp) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
        text.forEachIndexed { index, char ->
            key(index) {
                if (char == ':') Colon(height) else FlipDigit(char, tile, height)
            }
        }
    }
}

private val TileTop = Color(0xFF3A5A48)
private val TileBottom = Color(0xFF2F4A3A)
private val Digit = Color.White
private const val FLIP_MS = 520

@Composable
private fun Colon(height: Dp) {
    Column(Modifier.height(height), verticalArrangement = Arrangement.spacedBy(30.dp, Alignment.CenterVertically)) {
        repeat(2) { Box(Modifier.size(16.dp).background(TileBottom, RoundedCornerShape(4.dp))) }
    }
}

@Composable
private fun FlipDigit(char: Char, width: Dp, height: Dp) {
    var current by remember { mutableStateOf(char) }
    var previous by remember { mutableStateOf<Char?>(null) }
    // 0 → 1: la primera mitad cae la paleta de arriba (cifra anterior) y la segunda baja la de abajo (cifra nueva)
    val top = remember { Animatable(0f) }
    val bottom = remember { Animatable(0f) }
    LaunchedEffect(char) {
        if (char == current) return@LaunchedEffect
        previous = current
        current = char
        top.snapTo(0f)
        bottom.snapTo(90f)
        withContext(RealTimeMotion) {
            top.animateTo(-90f, tween(FLIP_MS / 2, easing = FastOutLinearInEasing))
            bottom.animateTo(0f, tween(FLIP_MS / 2, easing = LinearOutSlowInEasing))
        }
        previous = null
    }
    val half = height / 2
    val style = TextStyle(
        fontFamily = GeistMono,
        fontWeight = FontWeight.Medium,
        fontSize = 144.sp,
        lineHeight = 144.sp,
        color = Digit,
        textAlign = TextAlign.Center,
        lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both)
    )
    val old = previous
    val measurer = rememberTextMeasurer()
    val metrics = LocalDensity.current
    val widthPx = with(metrics) { width.toPx() }
    val heightPx = with(metrics) { height.toPx() }
    val resources = LocalResources.current
    val typeface = remember(resources) { resources.getFont(R.font.geist_mono_medium) }
    val textSizePx = with(metrics) { 144.sp.toPx() }
    // Solo los dígitos 0-9 se centran por tinta (caché compartida entre posiciones); el resto se dibuja sin offset
    fun inkOf(c: Char): Offset =
        if (c in '0'..'9') InkCache.get(c, textSizePx, widthPx, heightPx) { inkOffset(measurer, typeface, textSizePx, c, style, widthPx, heightPx) }
        else Offset.Zero
    val inkCurrent = inkOf(current)
    val inkOld = inkOf(old ?: current)
    Box(Modifier.size(width, height)) {
        // Placas fijas: arriba la cifra nueva; abajo la anterior hasta que la tapa la paleta que baja
        Column {
            Half(current, upper = true, width, half, height, style, inkCurrent)
            Half(old ?: current, upper = false, width, half, height, style, inkOld)
        }
        if (old != null) {
            Column {
                Half(
                    old, upper = true, width, half, height, style, inkOld,
                    Modifier.graphicsLayer {
                        transformOrigin = TransformOrigin(0.5f, 1f)
                        rotationX = top.value
                        cameraDistance = 12f * density
                        alpha = if (top.value <= -89f) 0f else 1f
                    }
                )
                Half(
                    current, upper = false, width, half, height, style, inkCurrent,
                    Modifier.graphicsLayer {
                        transformOrigin = TransformOrigin(0.5f, 0f)
                        rotationX = bottom.value
                        cameraDistance = 12f * density
                        alpha = if (bottom.value >= 89f) 0f else 1f
                    }
                )
            }
        }
    }
}

/** Caché de offsets de tinta compartida por todas las posiciones del reloj: se rasteriza una vez por dígito y tamaño. */
private object InkCache {
    private data class Key(val char: Char, val textSizePx: Float, val widthPx: Float, val heightPx: Float)

    private val map = HashMap<Key, Offset>()

    @Synchronized
    fun get(char: Char, textSizePx: Float, widthPx: Float, heightPx: Float, compute: () -> Offset): Offset =
        map.getOrPut(Key(char, textSizePx, widthPx, heightPx), compute)
}

/**
 * Desplazamiento (px) que lleva el centro de la tinta real de la cifra al centro de la placa. `Text` centra por caja
 * de línea y ancho de avance, no por la tinta (y `getPathForRange` devuelve la caja de línea, no el trazo), así que se
 * rasteriza la cifra fuera de pantalla con la misma fuente y tamaño y se escanean los píxeles con alfa > 0.
 */
private fun inkOffset(
    measurer: TextMeasurer, typeface: Typeface, textSizePx: Float, char: Char, style: TextStyle, widthPx: Float, heightPx: Float
): Offset {
    val layout = measurer.measure(char.toString(), style, maxLines = 1, constraints = Constraints(maxWidth = widthPx.toInt()))
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.typeface = typeface
        textSize = textSizePx
        color = android.graphics.Color.WHITE
    }
    val margin = ceil(textSizePx).toInt()
    val side = margin * 3
    val bitmap = createBitmap(side, side, Bitmap.Config.ALPHA_8)
    // Origen del glifo (x de inicio, línea base) en el bitmap
    Canvas(bitmap).drawText(char.toString(), margin.toFloat(), margin * 2f, paint)
    val alpha = ByteArray(side * side)
    bitmap.copyPixelsToBuffer(java.nio.ByteBuffer.wrap(alpha))
    bitmap.recycle()
    var minX = side; var maxX = -1; var minY = side; var maxY = -1
    for (y in 0 until side) for (x in 0 until side) {
        if (alpha[y * side + x].toInt() != 0) {
            if (x < minX) minX = x
            if (x > maxX) maxX = x
            if (y < minY) minY = y
            if (y > maxY) maxY = y
        }
    }
    if (maxX < 0) return Offset.Zero
    // Centro de la tinta respecto al origen del glifo (x de inicio, línea base)
    val inkCx = (minX + maxX + 1) / 2f - margin
    val inkCy = (minY + maxY + 1) / 2f - margin * 2f
    // El Text de Half se constriñe al alto de la placa (arranca arriba, sin centrado vertical) y se centra en horizontal
    val centerX = (widthPx - layout.size.width) / 2f + inkCx
    val centerY = layout.firstBaseline + inkCy
    return Offset(widthPx / 2f - centerX, heightPx / 2f - centerY)
}

/** Media placa: la cifra entera, del alto de la placa completa, recortada a su mitad de arriba o de abajo. */
@Composable
private fun Half(char: Char, upper: Boolean, width: Dp, half: Dp, full: Dp, style: TextStyle, ink: Offset, modifier: Modifier = Modifier) {
    val corner = 14.dp
    val shape = if (upper) RoundedCornerShape(topStart = corner, topEnd = corner) else RoundedCornerShape(bottomStart = corner, bottomEnd = corner)
    Box(
        modifier
            .size(width, half)
            .clip(shape)
            .background(Brush.verticalGradient(if (upper) listOf(TileTop, TileBottom) else listOf(TileBottom, TileTop.copy(alpha = 0.9f))))
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .wrapContentHeight(if (upper) Alignment.Top else Alignment.Bottom, unbounded = true)
                .height(full),
            contentAlignment = Alignment.Center
        ) {
            Text(
                char.toString(), style = style, maxLines = 1,
                modifier = Modifier.width(width).graphicsLayer { translationX = ink.x; translationY = ink.y }
            )
        }
    }
}
