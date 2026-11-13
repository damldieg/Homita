package com.lito.planify.dashboard.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.lito.planify.dashboard.R
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.hypot

/** Colores de la marca (brand/BRAND.md). `Palette` de la interfaz no cambia. */
object Brand {
    val Sage = Color(0xFF4F7A63)
    val Cream = Color(0xFFF4EFE6)
    val Mustard = Color(0xFFE9B44C)
    /** Igual que `Palette.Background` y que el fondo de la animación de arranque del marco. */
    val Launch = Color(0xFFF7EEE2)
}

/**
 * Animaciones de marca sobre el dashboard (réplica de HomitaIntro de la app iOS):
 *  - [First]: arranque sin sesión. Aparece el icono, se dibuja la h, se enciende la luz y sube el nombre (~2,4 s).
 *  - [Login]: justo tras iniciar sesión. Fondo salvia, la h se dibuja, la luz se enciende y se abre como círculo
 *    que descubre el panel (~1,8 s).
 *  - [Returning]: arranque con sesión ya iniciada. Versión corta que tapa la primera carga (~1,2 s).
 */
enum class IntroStyle { First, Login, Returning }

private val StemPath = Path().apply { moveTo(36f, 24f); lineTo(36f, 96f) }
private val RoofPath = Path().apply { moveTo(36f, 62f); lineTo(60f, 42f); lineTo(84f, 62f); lineTo(84f, 96f) }

/** Dibuja la «h de hogar» centrada en [c] con lado [size]; mismas proporciones que la cuadrícula 120×120 de la marca. */
private fun DrawScope.drawMark(
    c: Offset, size: Float, stem: Float, roof: Float, dot: Float, glow: Float, stroke: Color, light: Color,
) {
    val s = size / 120f
    val ox = c.x - 60f * s
    val oy = c.y - 60f * s
    val matrix = Matrix().apply { translate(ox, oy); scale(s, s) }
    fun part(src: Path, t: Float): Path {
        val m = PathMeasure()
        m.setPath(src, false)
        val out = Path()
        m.getSegment(0f, m.length * t, out, true)
        out.transform(matrix) // de la cuadrícula 120×120 al lado y posición pedidos
        return out
    }
    val style = Stroke(width = 12f * s, cap = StrokeCap.Round, join = StrokeJoin.Round)
    if (stem > 0.001f) drawPath(part(StemPath, stem), stroke, style = style)
    if (roof > 0.001f) drawPath(part(RoofPath, roof), stroke, style = style)
    val dc = Offset(ox + 60f * s, oy + 78f * s)
    if (glow > 0f) drawCircle(light.copy(alpha = 0.5f * (1f - glow)), radius = 7f * s * (1f + glow * 3.5f), center = dc)
    if (dot > 0f) drawCircle(light, radius = 7f * s * dot, center = dc)
}

@Composable
fun BrandIntro(style: IntroStyle, onFinish: () -> Unit) {
    val layer = remember { Animatable(1f) }
    val tile = remember { Animatable(0f) }
    val stem = remember { Animatable(0f) }
    val roof = remember { Animatable(0f) }
    val dot = remember { Animatable(0f) }
    val glow = remember { Animatable(0f) }
    val word = remember { Animatable(0f) }
    val bg = remember { Animatable(0f) }
    val reveal = remember { Animatable(0f) }

    LaunchedEffect(style) {
        coroutineScope {
            suspend fun lightOn() {
                launch { dot.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMediumLow)) }
                launch { glow.animateTo(1f, tween(700, easing = LinearOutSlowInEasing)) }
            }
            when (style) {
                IntroStyle.First -> {
                    launch { tile.animateTo(1f, tween(350, easing = LinearOutSlowInEasing)) }
                    delay(300)
                    launch { stem.animateTo(1f, tween(400, easing = LinearOutSlowInEasing)) }
                    delay(350)
                    launch { roof.animateTo(1f, tween(450, easing = FastOutSlowInEasing)) }
                    delay(450)
                    lightOn()
                    delay(300)
                    launch { word.animateTo(1f, tween(450, easing = LinearOutSlowInEasing)) }
                    delay(950)
                    layer.animateTo(0f, tween(350))
                }
                IntroStyle.Returning -> {
                    launch { tile.animateTo(1f, tween(200, easing = LinearOutSlowInEasing)) }
                    delay(100)
                    launch { stem.animateTo(1f, tween(300, easing = LinearOutSlowInEasing)) }
                    launch { roof.animateTo(1f, tween(300, easing = LinearOutSlowInEasing)) }
                    delay(300)
                    lightOn()
                    delay(500)
                    layer.animateTo(0f, tween(300))
                }
                IntroStyle.Login -> {
                    launch { bg.animateTo(1f, tween(250, easing = LinearOutSlowInEasing)) }
                    delay(100)
                    launch { stem.animateTo(1f, tween(300, easing = LinearOutSlowInEasing)) }
                    delay(200)
                    launch { roof.animateTo(1f, tween(350, easing = FastOutSlowInEasing)) }
                    delay(400)
                    lightOn()
                    delay(450)
                    reveal.animateTo(1f, tween(700, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)))
                }
            }
        }
        onFinish()
    }

    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = layer.value; compositingStrategy = CompositingStrategy.Offscreen }
            // Mientras tapa el panel no deja pasar toques; al abrirse el círculo, sí.
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        if (reveal.value == 0f) event.changes.forEach { it.consume() }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (style == IntroStyle.Login) {
            Canvas(Modifier.fillMaxSize()) {
                drawRect(Brand.Sage.copy(alpha = bg.value))
                val size = 200f
                drawMark(center, size, stem.value, roof.value, dot.value, glow.value, Brand.Cream, Brand.Mustard)
                if (reveal.value > 0f) {
                    // Agujero circular desde la luz: descubre el panel de debajo.
                    val hole = Offset(center.x, center.y + 18f * size / 120f)
                    drawCircle(Color.Transparent, radius = reveal.value * hypot(this.size.width, this.size.height), center = hole, blendMode = BlendMode.Clear)
                }
            }
        } else {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) { drawRect(Brand.Launch) }
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(40.dp)) {
                    val tileSize = if (style == IntroStyle.First) 220.dp else 190.dp
                    Canvas(Modifier.size(tileSize)) {
                        val k = 0.88f + 0.12f * tile.value
                        val side = this.size.minDimension * k
                        val topLeft = Offset((this.size.width - side) / 2f, (this.size.height - side) / 2f)
                        drawRoundRect(Brand.Sage.copy(alpha = tile.value), topLeft, Size(side, side), CornerRadius(side * 27f / 120f))
                        drawMark(center, side, stem.value, roof.value, dot.value, glow.value, Brand.Cream.copy(alpha = tile.value), Brand.Mustard)
                    }
                    if (style == IntroStyle.First) {
                        Image(
                            painterResource(R.drawable.homita_wordmark),
                            contentDescription = null,
                            modifier = Modifier
                                .height(76.dp)
                                .graphicsLayer { alpha = word.value; translationY = (1f - word.value) * 20f },
                        )
                    }
                }
            }
        }
    }
}
