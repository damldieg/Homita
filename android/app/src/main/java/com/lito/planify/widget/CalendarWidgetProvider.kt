package com.lito.planify.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.lito.planify.MainActivity
import com.lito.planify.R
import com.lito.planify.data.api.EventResponse
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.local.SessionManager
import com.lito.planify.util.AlarmHelper
import com.lito.planify.util.DateTimeUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/** Widget de eventos. [RoutineWidgetProvider] reutiliza el mismo diseño para las sesiones de rutinas. */
open class CalendarWidgetProvider : AppWidgetProvider() {

    protected open val routine = false

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        refresh(context, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_CLEAR_CACHE) {
            refresh(context, AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, this::class.java)))
            AlarmHelper.scheduleWidgetUpdate(context)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, routine)
    }

    /** Pinta al instante con la caché y vuelve a pintar cuando llegan los datos del servidor. */
    private fun refresh(context: Context, appWidgetIds: IntArray) {
        if (appWidgetIds.isEmpty()) return
        val manager = AppWidgetManager.getInstance(context)
        appWidgetIds.forEach { render(context, manager, it, routine) }

        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (EventWidgetData.fetch(context, routine)) {
                    appWidgetIds.forEach { render(context, manager, it, routine) }
                    AlarmHelper.synchronizeAlarms(context)
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {

        private val apiFormat get() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

        fun render(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, routine: Boolean) {
            val views = RemoteViews(context.packageName, R.layout.widget_calendar)
            views.setTextViewText(R.id.widget_empty_view, context.getString(if (routine) R.string.widget_empty_routines else R.string.widget_empty_events))

            // En la pantalla de bloqueo el widget es de solo lectura: sin acciones
            val isReadOnly = isLockScreenWidget(appWidgetManager, appWidgetId)
            val openApp = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).apply { data = Uri.parse(if (routine) "calendar://routines" else "calendar://global_events") },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val oneHourAgo = System.currentTimeMillis() - TimeUnit.HOURS.toMillis(1)
            val events = EventWidgetData.load(context, routine).filter { eventMillis(it) > oneHourAgo }.sortedBy { it.date_at }

            renderDays(context, views, events, openApp.takeUnless { isReadOnly })

            val items = RemoteViewsCompat.RemoteCollectionItems.Builder().setHasStableIds(true)
            events.take(10).forEach { items.addItem(it.id.toLong(), eventItem(context, it)) }
            RemoteViewsCompat.setRemoteAdapter(context, views, appWidgetId, R.id.widget_event_list, items.build())
            views.setEmptyView(R.id.widget_event_list, R.id.widget_empty_view)

            if (!isReadOnly) {
                views.setOnClickPendingIntent(R.id.widget_header_days_container, openApp)
                // La plantilla de las filas debe ser mutable para que Android añada el intent de cada fila.
                val itemTemplate = PendingIntent.getActivity(
                    context, 1,
                    Intent(context, MainActivity::class.java).apply { data = Uri.parse(if (routine) "calendar://routines" else "calendar://open_main_from_list") },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                views.setPendingIntentTemplate(R.id.widget_event_list, itemTemplate)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        /** Cabecera de 7 días con el número de eventos de cada día. */
        private fun renderDays(context: Context, views: RemoteViews, events: List<EventResponse>, onClick: PendingIntent?) {
            val counts = events.groupingBy { it.date_at.substringBefore(" ") }.eachCount()
            val today = LocalDate.now()
            views.removeAllViews(R.id.widget_header_days_container)

            for (i in 0..6) {
                val date = today.plusDays(i.toLong())
                val isToday = date == today
                val dayView = RemoteViews(context.packageName, R.layout.widget_day_item_header)
                dayView.setTextViewText(R.id.day_name, date.format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault())).replaceFirstChar { it.uppercaseChar() })
                dayView.setTextViewText(R.id.day_number, date.dayOfMonth.toString())
                dayView.setTextColor(R.id.day_name, Color.parseColor(if (isToday) "#3A1859" else "#5A5853"))
                dayView.setTextColor(R.id.day_number, Color.parseColor("#1D1B20"))
                dayView.setInt(R.id.day_container, "setBackgroundResource", if (isToday) R.drawable.widget_active_day_bg else 0)

                val count = counts[date.toString()] ?: 0
                if (count > 0) {
                    dayView.setViewVisibility(R.id.day_badge_container, View.VISIBLE)
                    dayView.setTextViewText(R.id.day_badge_text, count.toString())
                    // Rojo suave (mismo tono que la etiqueta "Hoy" de la app)
                    dayView.setInt(R.id.day_badge_bg, "setColorFilter", Color.parseColor("#E5484D"))
                } else {
                    dayView.setViewVisibility(R.id.day_badge_container, View.INVISIBLE)
                }

                onClick?.let { dayView.setOnClickPendingIntent(R.id.day_container, it) }
                views.addView(R.id.widget_header_days_container, dayView)
            }
        }

        private fun eventItem(context: Context, event: EventResponse): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_event_list_item)
            views.setTextViewText(R.id.event_title, event.title)
            views.setTextViewText(R.id.event_datetime, DateTimeUtils.formatEventDate(event.date_at))
            views.setViewVisibility(R.id.event_alarm_icon, if (event.alarm != null) View.VISIBLE else View.GONE)

            if (eventMillis(event) < System.currentTimeMillis()) {
                views.setTextColor(R.id.event_title, Color.parseColor("#9E9E9E"))
                views.setTextColor(R.id.event_datetime, Color.parseColor("#BDBDBD"))
                views.setInt(R.id.event_color_line, "setBackgroundColor", Color.parseColor("#E0E0E0"))
                views.setViewVisibility(R.id.badge_container, View.GONE)
            } else {
                views.setTextColor(R.id.event_title, Color.parseColor("#1D1B20"))
                views.setTextColor(R.id.event_datetime, Color.parseColor("#757575"))
                val color = try { Color.parseColor(event.calendar_color ?: "#6923E2") } catch (e: Exception) { Color.parseColor("#6923E2") }
                views.setInt(R.id.event_color_line, "setBackgroundColor", color)

                val relative = DateTimeUtils.getRelativeTime(context, event.date_at)
                if (relative.isNullOrBlank()) {
                    views.setViewVisibility(R.id.badge_container, View.GONE)
                } else {
                    views.setViewVisibility(R.id.badge_container, View.VISIBLE)
                    views.setTextViewText(R.id.event_relative_label, relative.uppercase(Locale.getDefault()))
                }
            }

            views.setOnClickFillInIntent(R.id.widget_item_root, Intent())
            return views
        }

        private fun eventMillis(event: EventResponse): Long =
            try { apiFormat.parse(event.date_at)?.time ?: 0L } catch (e: Exception) { 0L }
    }
}

class RoutineWidgetProvider : CalendarWidgetProvider() {
    override val routine = true
}

/** Caché persistente de los widgets de eventos y rutinas, para pintar sin red. */
internal object EventWidgetData {

    private fun prefs(context: Context) = context.getSharedPreferences("PlanifyWidgets", Context.MODE_PRIVATE)

    private fun key(routine: Boolean) = if (routine) "widget_routine_events_json" else "widget_calendar_events_json"

    fun load(context: Context, routine: Boolean): List<EventResponse> {
        val json = prefs(context).getString(key(routine), null) ?: return emptyList()
        return try {
            Gson().fromJson<List<EventResponse>>(json, object : TypeToken<List<EventResponse>>() {}.type) ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Descarga los próximos eventos (desde ayer) y los guarda. Devuelve false si no hay sesión o falla la red. */
    suspend fun fetch(context: Context, routine: Boolean): Boolean {
        val token = SessionManager(context).authTokenFlow.firstOrNull() ?: return false
        RetrofitClient.setToken(token)
        // El backend guarda fechas locales sin zona: enviamos la hora local como si fuera UTC.
        val now = System.currentTimeMillis()
        val yesterday = ((now + TimeZone.getDefault().getOffset(now) - TimeUnit.DAYS.toMillis(1)) / 1000).toString()
        return try {
            val response = RetrofitClient.apiService.getEvents(startDate = yesterday, limit = 20, widget = true, routine = routine)
            if (!response.isSuccessful) {
                Log.e("CalendarWidget", "API error: ${response.code()}")
                return false
            }
            prefs(context).edit().putString(key(routine), Gson().toJson(response.body() ?: emptyList<EventResponse>())).apply()
            true
        } catch (e: Exception) {
            Log.e("CalendarWidget", "Network error", e)
            false
        }
    }
}
