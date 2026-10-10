package com.lito.planify.util

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.lito.planify.MainActivity
import com.lito.planify.R
import com.lito.planify.data.api.EventResponse
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.local.SessionManager
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.text.SimpleDateFormat
import java.util.Locale

object AlarmHelper {
    private const val CHANNEL_ID = "event_alarms"
    private val syncMutex = Mutex()
    private val stateLock = Any()
    private var stateVersion = 0L

    suspend fun synchronizeAlarms(context: Context): Boolean = withContext(Dispatchers.IO) {
        syncMutex.withLock {
            val version = synchronized(stateLock) { stateVersion }
            val session = SessionManager(context)
            val token = session.authTokenFlow.firstOrNull()
            if (token == null) {
                cancelAll(context)
                return@withLock true
            }
            try {
                val now = System.currentTimeMillis()
                val localNow = ((now + java.util.TimeZone.getDefault().getOffset(now)) / 1000).toString()
                val response = RetrofitClient.apiService.getEvents(startDate = localNow)
                if (!response.isSuccessful) return@withLock false
                if (session.authTokenFlow.firstOrNull() != token) return@withLock false
                val events = response.body() ?: return@withLock false
                synchronized(stateLock) {
                    if (version != stateVersion) return@withLock false
                    reconcileAlarms(context, events)
                }
            } catch (e: Exception) {
                Log.e("AlarmHelper", "No se pudieron sincronizar los avisos", e)
                false
            }
        }
    }

    private fun cachedEvents(context: Context): List<EventResponse> {
        try {
            val json = context.getSharedPreferences("event_alarm_state", Context.MODE_PRIVATE).getString("events", null) ?: return emptyList()
            val type = object : TypeToken<List<EventResponse>>() {}.type
            return Gson().fromJson<List<EventResponse>>(json, type) ?: emptyList()
        } catch (e: Exception) {
            Log.e("AlarmHelper", "No se pudieron restaurar los avisos", e)
            return emptyList()
        }
    }

    private fun reconcileAlarms(context: Context, events: List<EventResponse>): Boolean {
        val selected = upcomingAlarms(events, System.currentTimeMillis())
        val ids = selected.map { it.id.toString() }.toSet()
        val prefs = context.getSharedPreferences("event_alarm_state", Context.MODE_PRIVATE)
        prefs.getStringSet("ids", emptySet()).orEmpty().filterNot { it in ids }
            .forEach { it.toIntOrNull()?.let { id -> cancelAlarm(context, id) } }
        if (!prefs.edit().putStringSet("ids", ids).putString("events", Gson().toJson(events)).commit()) return false
        selected.forEach { scheduleAlarm(context, it) }
        return true
    }

    // Keep room for widget alarms below Android's per-app limit; fired alarms refill from cache.
    internal fun upcomingAlarms(events: List<EventResponse>, now: Long): List<EventResponse> =
        events.mapNotNull { event -> alarmTime(event)?.takeIf { it > now }?.let { event to it } }
            .sortedBy { it.second }.take(450).map { it.first }

    private fun alarmTime(event: EventResponse): Long? {
        val alarm = event.alarm ?: return null
        val date = try { SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).parse(event.date_at) }
            catch (e: Exception) { null } ?: return null
        return date.time - alarm * 60_000L
    }

    fun rescheduleCachedAlarms(context: Context) = synchronized(stateLock) {
        reconcileAlarms(context, cachedEvents(context))
    }

    suspend fun rememberEvent(context: Context, event: EventResponse) = withContext(Dispatchers.IO) {
        synchronized(stateLock) {
            stateVersion++
            reconcileAlarms(context, cachedEvents(context).filterNot { it.id == event.id } + event)
        }
    }

    fun cancelRoutineAlarms(context: Context, routineId: Int) = synchronized(stateLock) {
        stateVersion++
        cachedEvents(context).filter { it.routine_id == routineId }.forEach { cancelAlarm(context, it.id) }
    }

    fun cancelAll(context: Context) = synchronized(stateLock) {
        stateVersion++
        val prefs = context.getSharedPreferences("event_alarm_state", Context.MODE_PRIVATE)
        prefs.getStringSet("ids", emptySet()).orEmpty().forEach { it.toIntOrNull()?.let { id -> cancelAlarm(context, id) } }
        prefs.edit().clear().apply()
    }

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Avisos de Eventos"
            val descriptionText = "Notificaciones para los eventos programados"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun scheduleWidgetUpdate(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Tareas Widget
        val taskIntent = Intent(context, com.lito.planify.widget.TasksWidgetProvider::class.java).apply {
            action = "com.lito.planify.widget.ACTION_CLEAR_CACHE"
        }
        val pendingTask = PendingIntent.getBroadcast(
            context,
            2001,
            taskIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Calendario Widget
        val calendarIntent = Intent(context, com.lito.planify.widget.CalendarWidgetProvider::class.java).apply {
            action = "com.lito.planify.widget.ACTION_CLEAR_CACHE"
        }
        val pendingCalendar = PendingIntent.getBroadcast(
            context,
            2002,
            calendarIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Rutinas Widget
        val routineIntent = Intent(context, com.lito.planify.widget.RoutineWidgetProvider::class.java).apply {
            action = "com.lito.planify.widget.ACTION_CLEAR_CACHE"
        }
        val pendingRoutine = PendingIntent.getBroadcast(
            context,
            2003,
            routineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val interval = 15 * 60 * 1000L // 15 minutos

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC,
                System.currentTimeMillis() + interval,
                pendingTask
            )
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC,
                System.currentTimeMillis() + interval,
                pendingCalendar
            )
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC,
                System.currentTimeMillis() + interval,
                pendingRoutine
            )
        } else {
            alarmManager.set(
                AlarmManager.RTC,
                System.currentTimeMillis() + interval,
                pendingTask
            )
            alarmManager.set(
                AlarmManager.RTC,
                System.currentTimeMillis() + interval,
                pendingCalendar
            )
            alarmManager.set(
                AlarmManager.RTC,
                System.currentTimeMillis() + interval,
                pendingRoutine
            )
        }
    }

    private fun scheduleAlarm(context: Context, event: EventResponse) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("eventId", event.id)
            putExtra("eventTitle", event.title)
            putExtra("calendarName", event.calendar_name)
            putExtra("calendarColor", event.calendar_color)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            event.id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (event.alarm == null) {
            alarmManager.cancel(pendingIntent)
            return
        }

        val alarmTime = alarmTime(event) ?: return
        Log.d("AlarmHelper", "Intentando programar alarma para: ${event.title} a las $alarmTime (Actual: ${System.currentTimeMillis()})")

        if (alarmTime > System.currentTimeMillis()) {
            Log.d("AlarmHelper", "Programando alarma con antelación...")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        Log.d("AlarmHelper", "Usando exact alarm")
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmTime, pendingIntent)
                    } else {
                        Log.d("AlarmHelper", "Usando inexact alarm")
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmTime, pendingIntent)
                    }
                } else {
                    Log.d("AlarmHelper", "Usando exact alarm < S")
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarmTime, pendingIntent)
                }
            } catch (e: SecurityException) {
                Log.d("AlarmHelper", "Usando basic alarm por SecurityException")
                alarmManager.set(AlarmManager.RTC_WAKEUP, alarmTime, pendingIntent)
            }
        } else {
            alarmManager.cancel(pendingIntent)
            Log.d("AlarmHelper", "No se programó porque alarmTime es pasado.")
        }
    }

    fun cancelAlarm(context: Context, eventId: Int) = synchronized(stateLock) {
        stateVersion++
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            eventId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
        val prefs = context.getSharedPreferences("event_alarm_state", Context.MODE_PRIVATE)
        prefs.edit().putStringSet("ids", prefs.getStringSet("ids", emptySet()).orEmpty() - eventId.toString())
            .putString("events", Gson().toJson(cachedEvents(context).filterNot { it.id == eventId })).apply()
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getIntExtra("eventId", -1)
        if (eventId == -1) return
        val title = intent.getStringExtra("eventTitle") ?: "Evento"
        val calendarName = intent.getStringExtra("calendarName")
        val calendarColor = intent.getStringExtra("calendarColor")

        val mainIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(context, eventId, mainIntent, PendingIntent.FLAG_IMMUTABLE)

        val fullScreenIntent = Intent(context, com.lito.planify.ui.screens.AlarmActivity::class.java).apply {
            putExtra("eventId", eventId)
            putExtra("eventTitle", title)
            putExtra("calendarName", calendarName)
            putExtra("calendarColor", calendarColor)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            eventId,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, "event_alarms")
            .setSmallIcon(R.drawable.ic_calendar_fg)
            .setContentTitle(title)
            .setContentText(if (calendarName != null) "En calendario: $calendarName" else "Planify")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(eventId, builder.build())
        val pendingResult = goAsync()
        @Suppress("OPT_IN_USAGE")
        GlobalScope.launch(Dispatchers.IO) {
            try {
                AlarmHelper.cancelAlarm(context, eventId)
                AlarmHelper.rescheduleCachedAlarms(context)
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "No se pudieron renovar los avisos", e)
            } finally {
                pendingResult.finish()
            }
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)) {
            AlarmHelper.scheduleWidgetUpdate(context)
            val pendingResult = goAsync()
            @Suppress("OPT_IN_USAGE")
            GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val sm = SessionManager(context)
                    val token = sm.authTokenFlow.firstOrNull()
                    if (token != null) {
                        RetrofitClient.setToken(token)
                        AlarmHelper.rescheduleCachedAlarms(context)
                        AlarmHelper.synchronizeAlarms(context)
                    } else {
                        AlarmHelper.cancelAll(context)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                } finally {
                    pendingResult.finish()
                }
            }
        }
    }
}
