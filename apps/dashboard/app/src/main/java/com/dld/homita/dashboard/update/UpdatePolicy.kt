package com.dld.homita.dashboard.update

import com.dld.homita.dashboard.data.UpdateCheck
import java.io.File
import java.security.MessageDigest

/**
 * Decisiones de la actualización remota (dashboard-actualizacion-remota), sin efectos: cuándo comprobar, cuándo una oferta
 * es de verdad más nueva, cuándo se puede instalar y si lo descargado coincide con lo publicado.
 */
object UpdatePolicy {
    /** Una comprobación al día; si falla, se reintenta en una hora (ver [retryAfterFailureMs]). */
    const val CHECK_EVERY_MS = 24L * 60 * 60 * 1000
    const val RETRY_AFTER_FAILURE_MS = 60L * 60 * 1000

    fun shouldCheck(lastCheckMs: Long, nowMs: Long): Boolean = nowMs - lastCheckMs >= CHECK_EVERY_MS

    /** Tras un fallo de comprobación, la próxima se pide antes: la marca se adelanta para que [shouldCheck] la deje pasar. */
    fun lastCheckAfterFailure(nowMs: Long): Long = nowMs - CHECK_EVERY_MS + RETRY_AFTER_FAILURE_MS

    /** Versión nueva de verdad: el servidor la ofrece, es mayor que la instalada y trae URL, hash y tamaño. */
    fun offerIsNewer(offer: UpdateCheck, installedCode: Int): Boolean {
        val code = offer.version_code ?: return false
        return offer.update && code > installedCode && offer.url != null && offer.sha256 != null && (offer.size ?: 0L) > 0L
    }

    /**
     * Instalar solo con la pantalla apagada por horario (las pantallas sin horario no se actualizan solas, y se ve en
     * Diagnóstico) y con reloj válido: sin NTP la hora del marco es falsa y no se confía en el horario.
     */
    fun mayInstall(clockValid: Boolean, scheduleEnabled: Boolean, screenOn: Boolean): Boolean =
        clockValid && scheduleEnabled && !screenOn

    /**
     * Valor seguro para una cabecera HTTP: OkHttp rechaza caracteres no ASCII («al día» rompía la petición), así que se
     * quitan los acentos y cualquier carácter fuera de ASCII imprimible.
     */
    fun headerValue(text: String?): String? = text?.let {
        java.text.Normalizer.normalize(it, java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{M}"), "")
            .replace(Regex("[^\\x20-\\x7E]"), "?")
    }

    /** La URL del APK llega como ruta (`/storage/v1/...`): se resuelve contra el origen de la URL base de la app. */
    fun absoluteUrl(baseUrl: String, url: String): String {
        if (url.startsWith("http://") || url.startsWith("https://")) return url
        val base = java.net.URI(baseUrl)
        return "${base.scheme}://${base.authority}$url"
    }

    /** Tamaño y SHA-256 del archivo descargado frente a lo publicado. */
    fun verify(expectedSha256: String, expectedSize: Long, file: File): Boolean =
        file.length() == expectedSize && sha256(file).equals(expectedSha256, ignoreCase = true)

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
