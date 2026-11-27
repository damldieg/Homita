package com.dld.homita.dashboard.update

import android.content.Context
import com.dld.homita.dashboard.data.Store
import com.dld.homita.dashboard.data.UpdateCheck
import okhttp3.OkHttpClient
import java.io.File
import java.io.IOException

/**
 * Estado de la actualización de la pantalla (dashboard-actualizacion-remota): guarda la comprobación, descarga la oferta
 * verificada y la instala en horario de apagado. Las decisiones están en [UpdatePolicy].
 */
class DisplayUpdater(
    private val store: Store,
    private val dir: File,
    private val installedCode: () -> Int,
    private val downloader: ApkDownloader = ApkDownloader(OkHttpClient()),
) {
    private fun partFile(code: Int) = File(dir, "homita-$code.apk.part")
    fun readyFile(code: Int) = File(dir, "homita-$code.apk")

    /** Registra la comprobación: canal, marca de tiempo y lo que dice para el informe. */
    fun recordCheck(offer: UpdateCheck, nowMs: Long) {
        store.updateChannel = offer.channel
        store.updateLastCheckAt = nowMs
        store.updateResult = if (UpdatePolicy.offerIsNewer(offer, installedCode())) {
            "disponible ${offer.version_code}"
        } else {
            "al día"
        }
    }

    /** Un fallo de comprobación se reintenta pronto, no al día siguiente. */
    fun recordCheckFailure(nowMs: Long, reason: String) {
        store.updateLastCheckAt = UpdatePolicy.lastCheckAfterFailure(nowMs)
        store.updateResult = "fallo: $reason"
    }

    /** Descarga y verifica la oferta (en IO). Deja el APK listo para instalar, o lanza error. */
    fun download(offer: UpdateCheck): File {
        val code = requireNotNull(offer.version_code)
        val url = requireNotNull(offer.url)
        val sha = requireNotNull(offer.sha256)
        val size = requireNotNull(offer.size)
        dir.mkdirs()
        val part = partFile(code)
        downloader.download(url, size, part)
        if (!UpdatePolicy.verify(sha, size, part)) {
            part.delete()
            store.updateResult = "fallo: verificación del APK"
            throw IOException("El APK descargado no coincide con el manifiesto")
        }
        val ready = readyFile(code)
        ready.delete()
        if (!part.renameTo(ready)) throw IOException("No se pudo dejar listo el APK")
        store.updateReadyCode = code
        store.updateResult = "descargada $code"
        return ready
    }

    /** Instala la versión lista si toca (horario de apagado, reloj válido) y es de verdad más nueva. */
    fun installIfReady(context: Context, mayInstall: Boolean) {
        val code = store.updateReadyCode ?: return
        val ready = readyFile(code)
        // Ya instalada (o el archivo no está): se limpia para no reinstalar ni dejar el APK en disco.
        if (!ready.exists() || code <= installedCode()) {
            ready.delete()
            store.updateReadyCode = null
            return
        }
        if (!mayInstall) return
        ApkInstaller.install(context, ready)
    }
}
