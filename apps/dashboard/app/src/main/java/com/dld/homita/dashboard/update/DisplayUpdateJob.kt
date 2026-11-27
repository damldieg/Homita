package com.dld.homita.dashboard.update

import android.content.Context
import com.dld.homita.dashboard.BuildConfig
import com.dld.homita.dashboard.data.Diagnostics
import com.dld.homita.dashboard.data.DisplayApi
import com.dld.homita.dashboard.data.Session
import com.dld.homita.dashboard.data.Store
import com.dld.homita.dashboard.data.UpdateCheck
import com.dld.homita.dashboard.data.bodyOrThrow
import com.dld.homita.dashboard.data.repository.bearer
import com.dld.homita.dashboard.power.ScreenSchedule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDateTime

/**
 * Una pasada de la actualización remota (dashboard-actualizacion-pantalla-apagada): comprobación si toca, descarga si hay
 * oferta con horario, e instalación si la pantalla está apagada por horario. La ejecutan el ViewModel (con la pantalla
 * visible) y el worker de WorkManager (también con la actividad parada). Un solo tick a la vez en el proceso.
 */
class DisplayUpdateJob(
    private val context: Context,
    private val store: Store,
    private val displayApi: DisplayApi,
    private val session: Session,
    private val updater: DisplayUpdater,
    private val report: (String, Result<*>) -> Unit = { _, _ -> },
) {
    suspend fun tick(clockValid: Boolean, nowMs: Long = System.currentTimeMillis()) {
        if (store.displayId == null || store.token == null || !clockValid) return
        if (!lock.tryLock()) return
        try {
            check(nowMs)
            install()
        } finally {
            lock.unlock()
        }
    }

    private suspend fun check(nowMs: Long) {
        if (!UpdatePolicy.shouldCheck(store.updateLastCheckAt, nowMs)) return
        val result = session.authorized { token ->
            runCatching {
                displayApi.update(bearer(token), BuildConfig.VERSION_CODE.toString(), BuildConfig.VERSION_NAME,
                    UpdatePolicy.headerValue(store.updateResult)).bodyOrThrow()
            }
        }
        report("actualización", result)
        result.onSuccess { offer ->
            updater.recordCheck(offer, nowMs)
            // Solo se descarga si la pantalla tiene horario: sin horario no se baja nada (R1-03).
            if (UpdatePolicy.offerIsNewer(offer, BuildConfig.VERSION_CODE) && store.schedule.enabled) download(offer)
        }.onFailure { updater.recordCheckFailure(nowMs, Diagnostics.describe(it)) }
    }

    private suspend fun download(offer: UpdateCheck) {
        val absolute = offer.copy(url = UpdatePolicy.absoluteUrl(BuildConfig.BASE_URL, offer.url!!))
        val result = runCatching { withContext(Dispatchers.IO) { updater.download(absolute) } }
        report("descarga de actualización", result)
        result.onFailure { updater.recordCheckFailure(System.currentTimeMillis(), Diagnostics.describe(it)) }
    }

    private suspend fun install() {
        val schedule = store.schedule
        val screenOn = !schedule.enabled || ScreenSchedule.isOn(schedule, LocalDateTime.now())
        val mayInstall = UpdatePolicy.mayInstall(clockValid = true, scheduleEnabled = schedule.enabled, screenOn = screenOn)
        val result = withContext(Dispatchers.IO) {
            runCatching { updater.installIfReady(context, mayInstall, System.currentTimeMillis()) }
        }
        report("instalación de actualización", result)
    }

    companion object {
        private val lock = Mutex()
    }
}

/** Piezas compartidas por la app y el worker: un solo `Session` (un solo refresco de token a la vez) y el job. */
object DisplayUpdates {
    @Volatile private var session: Session? = null

    fun session(store: Store): Session = session ?: synchronized(this) {
        session ?: Session(store, { refresh -> com.dld.homita.dashboard.data.Api.client.refresh(
            com.dld.homita.dashboard.data.RefreshRequest(refresh)) }).also { session = it }
    }

    fun job(context: Context, store: Store, report: (String, Result<*>) -> Unit = { _, _ -> }): DisplayUpdateJob =
        DisplayUpdateJob(context, store, DisplayApi.client, session(store),
            DisplayUpdater(store, File(context.filesDir, "update"), installedCode = { BuildConfig.VERSION_CODE }), report)
}
