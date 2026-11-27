package com.dld.homita.dashboard.ui

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import android.graphics.Bitmap

/**
 * QR de vinculación (dashboard-vinculacion-qr): el código de 6 dígitos que ya muestra la pantalla, en QR, para que el móvil
 * lo lea en vez de escribirlo. Sin datos nuevos: el QR solo lleva el código.
 */
object PairingQr {
    /** Matriz de módulos del QR (true = negro), con un margen de silencio de 4 módulos. */
    fun matrix(payload: String): BitMatrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, 0, 0)

    /** Píxeles ARGB de la matriz escalada a [sizePx] (sin el margen de la matriz). */
    fun pixels(matrix: BitMatrix, sizePx: Int): IntArray {
        val width = matrix.width
        val scale = sizePx / width
        val size = width * scale
        val pixels = IntArray(size * size)
        for (y in 0 until size) for (x in 0 until size) {
            pixels[y * size + x] = if (matrix.get(x / scale, y / scale)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
        }
        return pixels
    }

    /** Imagen lista para Compose. */
    fun image(payload: String, sizePx: Int): ImageBitmap {
        val matrix = matrix(payload)
        val scale = sizePx / matrix.width
        val size = matrix.width * scale
        val bitmap = Bitmap.createBitmap(pixels(matrix, sizePx), size, size, Bitmap.Config.ARGB_8888)
        return bitmap.asImageBitmap()
    }
}
