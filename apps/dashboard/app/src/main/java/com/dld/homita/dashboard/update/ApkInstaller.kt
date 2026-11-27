package com.dld.homita.dashboard.update

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import com.dld.homita.dashboard.data.Store
import java.io.File

/**
 * Instalación con PackageInstaller (dashboard-actualizacion-remota). La app es Device Owner: la sesión se confirma sin
 * intervención. El resultado vuelve a [UpdateResultReceiver].
 */
object ApkInstaller {
    fun install(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            .apply { setAppPackageName(context.packageName) }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("homita.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val intent = Intent(context, UpdateResultReceiver::class.java)
            val pending = PendingIntent.getBroadcast(
                context, sessionId, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            session.commit(pending.intentSender)
        }
    }
}

/** Resultado de la instalación: queda como último resultado de actualización (cabecera de la próxima petición). */
class UpdateResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val store = Store(context)
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        when (status) {
            PackageInstaller.STATUS_SUCCESS -> {
                store.updateResult = "instalada ${store.updateReadyCode ?: "?"}"
                store.updateReadyCode = null
            }
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Sin Device Owner el sistema pide confirmación: se lanza, pero el marco no debería llegar aquí.
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)?.let {
                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(it)
                }
                store.updateResult = "pendiente de confirmación"
            }
            else -> {
                store.updateResult = "fallo: ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: status}"
                store.updateReadyCode = null
            }
        }
    }
}
