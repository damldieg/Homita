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
import java.text.SimpleDateFormat
import java.util.Locale

object AlarmHelper {
    private const val CHANNEL_ID = "event_alarms"

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

        val interval = AlarmManager.INTERVAL_HALF_HOUR

        alarmManager.setInexactRepeating(
            AlarmManager.RTC,
            System.currentTimeMillis() + interval,
            interval,
            pendingTask
        )
        alarmManager.setInexactRepeating(
            AlarmManager.RTC,
            System.currentTimeMillis() + interval,
            interval,
            pendingCalendar
        )
    }

    fun scheduleAlarm(context: Context, event: EventResponse) {
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

        val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        val date = try { sdf.parse(event.date_at) } catch(e: Exception) { null } ?: return
        val alarmTime = date.time - (event.alarm * 60 * 1000L)

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
            Log.d("AlarmHelper", "No se programó porque alarmTime es pasado.")
        }
    }

    fun cancelAlarm(context: Context, eventId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            eventId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
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
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            AlarmHelper.scheduleWidgetUpdate(context)
            val pendingResult = goAsync()
            @Suppress("OPT_IN_USAGE")
            GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val sm = SessionManager(context)
                    val token = sm.authTokenFlow.firstOrNull()
                    if (token != null) {
                        RetrofitClient.setToken(token)
                        val nowMillis = System.currentTimeMillis()
                        val offset = java.util.TimeZone.getDefault().getOffset(nowMillis)
                        val localNowSeconds = ((nowMillis + offset) / 1000).toString()
                        val response = RetrofitClient.apiService.getEvents(startDate = localNowSeconds)
                        if (response.isSuccessful) {
                            val events = response.body() ?: emptyList()
                            events.forEach { event ->
                                AlarmHelper.scheduleAlarm(context, event)
                            }
                        }
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
