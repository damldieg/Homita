package com.dld.homita.dashboard.update

import com.dld.homita.dashboard.data.UpdateCheck
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Política de la actualización remota (dashboard-actualizacion-remota): sin red ni Android. */
class UpdatePolicyTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val hour = 60L * 60 * 1000
    private val day = 24 * hour
    private val sha = "6bcfe2b58f265ce785fa6177e38758fed1676130d7160463f77bdaa02027a25a"
    private fun offer(code: Int? = 7, update: Boolean = true, url: String? = "https://x/y.apk", hash: String? = sha, size: Long? = 11L) =
        UpdateCheck(channel = "estable", update = update, version_code = code, sha256 = hash, size = size, url = url)

    @Test
    fun laComprobacionEsDiariaYUnFalloSeReintentaAlaHora() {
        val now = 100 * day
        assertFalse(UpdatePolicy.shouldCheck(lastCheckMs = now - hour, nowMs = now))
        assertTrue(UpdatePolicy.shouldCheck(lastCheckMs = now - day, nowMs = now))
        val afterFailure = UpdatePolicy.lastCheckAfterFailure(now)
        assertFalse(UpdatePolicy.shouldCheck(lastCheckMs = afterFailure, nowMs = now))
        assertTrue(UpdatePolicy.shouldCheck(lastCheckMs = afterFailure, nowMs = now + hour))
    }

    @Test
    fun laOfertaSoloCuentaSiEsDeVerdadMasNueva() {
        assertTrue(UpdatePolicy.offerIsNewer(offer(code = 7), installedCode = 6))
        assertFalse("misma versión", UpdatePolicy.offerIsNewer(offer(code = 7), installedCode = 7))
        assertFalse("versión anterior: PackageInstaller no baja", UpdatePolicy.offerIsNewer(offer(code = 5), installedCode = 6))
        assertFalse("el servidor dice que no hay", UpdatePolicy.offerIsNewer(offer(update = false), installedCode = 6))
        assertFalse("sin URL", UpdatePolicy.offerIsNewer(offer(url = null), installedCode = 6))
        assertFalse("sin hash", UpdatePolicy.offerIsNewer(offer(hash = null), installedCode = 6))
        assertFalse("tamaño cero", UpdatePolicy.offerIsNewer(offer(size = 0L), installedCode = 6))
        assertFalse("sin versión", UpdatePolicy.offerIsNewer(offer(code = null), installedCode = 6))
    }

    @Test
    fun instalarSoloDeNocheConRelojValidoYHorarioActivo() {
        assertTrue(UpdatePolicy.mayInstall(clockValid = true, scheduleEnabled = true, screenOn = false))
        assertFalse("pantalla encendida", UpdatePolicy.mayInstall(clockValid = true, scheduleEnabled = true, screenOn = true))
        assertFalse("reloj sin NTP", UpdatePolicy.mayInstall(clockValid = false, scheduleEnabled = true, screenOn = false))
        assertFalse("sin horario de apagado", UpdatePolicy.mayInstall(clockValid = true, scheduleEnabled = false, screenOn = false))
    }

    @Test
    fun laVerificacionComparaTamañoYSha256() {
        val apk = folder.newFile("homita.apk")
        apk.writeBytes("homita-apk".toByteArray())
        assertTrue(UpdatePolicy.verify(sha, 10L, apk))
        assertTrue("hash en mayúsculas también vale", UpdatePolicy.verify(sha.uppercase(), 10L, apk))
        assertFalse("tamaño distinto", UpdatePolicy.verify(sha, 11L, apk))
        assertFalse("contenido alterado", UpdatePolicy.verify("0".repeat(64), 10L, apk))
    }
}
