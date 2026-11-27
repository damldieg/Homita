package com.dld.homita.dashboard.update

import com.dld.homita.dashboard.data.HttpError
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Descarga reanudable del APK (dashboard-actualizacion-remota). Escribe en trozos a disco (el marco tiene 1 GB de RAM y
 * Wi-Fi de 2,4 GHz): si se corta, la siguiente vez pide el resto con `Range`. Un 403 suele ser una URL firmada caducada:
 * no se borra lo ya descargado, la próxima comprobación trae una URL nueva.
 */
class ApkDownloader(private val http: OkHttpClient) {
    fun download(url: String, expectedSize: Long, part: File) {
        var have = if (part.exists()) part.length() else 0L
        if (have > expectedSize) {
            part.delete()
            have = 0L
        }
        if (have == expectedSize) return
        val request = Request.Builder().url(url).apply { if (have > 0) header("Range", "bytes=$have-") }.build()
        http.newCall(request).execute().use { response ->
            if (response.code == 416) {
                part.delete()
                throw IOException("rango no válido: se empieza de cero")
            }
            if (!response.isSuccessful) throw HttpError(response.code)
            // 206 = el servidor respetó el rango y se añade al final; 200 = cuerpo completo, se reescribe desde cero.
            val append = response.code == 206 && have > 0
            val body = response.body ?: throw IOException("respuesta sin cuerpo")
            FileOutputStream(part, append).use { out -> body.byteStream().use { it.copyTo(out, 64 * 1024) } }
        }
    }
}
