package com.dld.homita.dashboard.update

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.dld.homita.dashboard.data.Store
import com.dld.homita.dashboard.power.ScreenSchedule
import java.util.concurrent.TimeUnit

/**
 * Worker periódico de la actualización remota: corre aunque la actividad esté parada (pantalla apagada por horario), que
 * es justo cuando debe instalar. Cada hora, con red.
 */
class UpdateWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val store = Store(applicationContext)
        if (store.displayId == null || store.token == null) return Result.success()
        DisplayUpdates.job(applicationContext, store).tick(clockValid = ScreenSchedule.clockValid())
        return Result.success()
    }
}

object UpdateScheduler {
    private const val NAME = "display-update"

    /** Deja programada la pasada horaria (idempotente: KEEP no duplica el trabajo). */
    fun ensure(context: Context) {
        val request = PeriodicWorkRequestBuilder<UpdateWorker>(1, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }
}
