package com.lito.planify.widget

import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.lito.planify.R
import com.lito.planify.data.api.EventResponse
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.local.SessionManager
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking
import java.time.LocalDate

class WidgetRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return WidgetViewsFactory(this.applicationContext)
    }
}

class WidgetViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    
    private var events: List<EventResponse> = emptyList()

    companion object {
        var cachedEvents: List<EventResponse> = emptyList()
        var lastFetchTime: Long = 0
        var lastRedrawTime: Long = 0

        fun clearCache(@Suppress("UNUSED_PARAMETER") context: Context) {
            // No borramos la caché de persistencia para evitar pantallas en blanco si la red falla.
            // Solamente forzamos que la próxima vez se re-descargue todo.
            lastFetchTime = 0
            lastRedrawTime = 0
            cachedEvents = emptyList()
        }
        
        fun loadCache(context: Context): List<EventResponse> {
            if (cachedEvents.isNotEmpty()) return cachedEvents
            val prefs = context.getSharedPreferences("PlanifyWidgets", Context.MODE_PRIVATE)
            val json = prefs.getString("widget_calendar_events_json", null) ?: return emptyList()
            try {
                val type = object : TypeToken<List<EventResponse>>() {}.type
                cachedEvents = Gson().fromJson(json, type) ?: emptyList()
            } catch (e: Exception) {}
            return cachedEvents
        }

        fun saveCache(context: Context, events: List<EventResponse>) {
            cachedEvents = events
            val prefs = context.getSharedPreferences("PlanifyWidgets", Context.MODE_PRIVATE)
            prefs.edit().putString("widget_calendar_events_json", Gson().toJson(events)).apply()
        }

        fun getEventCountsPerDay(context: Context): Map<String, Pair<Int, String>> {
            val counts = mutableMapOf<String, Pair<Int, String>>()
            val oneHourAgo = System.currentTimeMillis() - (60 * 60 * 1000)
            val apiFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())

            loadCache(context).forEach { event ->
                try {
                    val eventTime = apiFormat.parse(event.date_at)?.time ?: 0L
                    if (eventTime > oneHourAgo) {
                        val datePart = event.date_at.substringBefore(" ")
                        val current = counts.getOrDefault(datePart, Pair(0, event.calendar_color ?: "#6923E2"))
                        counts[datePart] = Pair(current.first + 1, current.second)
                    }
                } catch (e: Exception) {}
            }
            return counts
        }
    }

    override fun onCreate() {}

    override fun onDataSetChanged() {
        runBlocking {
            try {
                val currentTime = System.currentTimeMillis()
                
                // Cargar primero desde caché persistente si está vacía
                val currentCache = WidgetViewsFactory.loadCache(context)

                if (currentTime - lastFetchTime > 1 * 60 * 1000 || currentCache.isEmpty()) {
                    val sessionManager = SessionManager(context)
                    val token = sessionManager.authTokenFlow.firstOrNull()

                    if (token != null) {
                        RetrofitClient.setToken(token)
                        val nowMillis = System.currentTimeMillis()
                        val offset = java.util.TimeZone.getDefault().getOffset(nowMillis)
                        val yesterdayMillis = (nowMillis + offset) - java.util.concurrent.TimeUnit.DAYS.toMillis(1)
                        val yesterdaySeconds = (yesterdayMillis / 1000).toString()
                        val response = RetrofitClient.apiService.getEvents(startDate = yesterdaySeconds, limit = 20, widget = true)
                        if (response.isSuccessful) {
                            val newEvents = response.body() ?: emptyList()
                            WidgetViewsFactory.saveCache(context, newEvents)
                            lastFetchTime = currentTime
                        } else {
                            Log.e("CalendarWidget", "API error: ${response.code()}")
                        }
                    } else {
                        Log.e("CalendarWidget", "Token is null. Cannot fetch events.")
                    }
                }
            } catch (e: Exception) {
                // El error de red (Ej. modo avión) se captura aquí para no romper el pintado de la caché local
                Log.e("CalendarWidget", "Network Exception in onDataSetChanged", e)
            }

            try {
                // Siempre cargar caché final para mostrar (ya sea vieja o recién actualizada)
                val finalCache = WidgetViewsFactory.loadCache(context)
                
                val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
                val selectedDateStr = prefs.getString("selected_date", null)
                val oneHourAgo = System.currentTimeMillis() - (60 * 60 * 1000)
                val apiFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())

                val filterValidEvents: (EventResponse) -> Boolean = { event ->
                    try {
                        val eventTime = apiFormat.parse(event.date_at)?.time ?: 0L
                        eventTime > oneHourAgo
                    } catch (e: Exception) { true }
                }

                events = if (selectedDateStr != null) {
                    finalCache.filter { it.date_at.startsWith(selectedDateStr) }
                        .filter(filterValidEvents)
                        .sortedBy { it.date_at }
                        .take(10)
                } else {
                    finalCache.filter(filterValidEvents)
                        .sortedBy { it.date_at }
                        .take(10)
                }
            } catch (e: Exception) {
                Log.e("CalendarWidget", "Exception in parsing cache", e)
            }

            // Evitar bucle infinito: no redibujar si no han pasado al menos 5 segundos desde el último redibujado.
            // NotifyAppWidgetViewDataChanged -> onDataSetChanged -> ACTION_REDRAW_HEADER -> updateAppWidget
            val currentMillis = System.currentTimeMillis()
            if (currentMillis - lastRedrawTime < 5000) {
                return@runBlocking
            }
            lastRedrawTime = currentMillis

            // Avisamos al widget provider de que ya tenemos los datos frescos para que pueda redibujar la cabecera (los puntos)
            val updateHeaderIntent = Intent("com.lito.planify.widget.ACTION_REDRAW_HEADER")
            updateHeaderIntent.component = android.content.ComponentName(context, CalendarWidgetProvider::class.java)
            context.sendBroadcast(updateHeaderIntent)
        }
    }

    override fun onDestroy() {
        events = emptyList()
    }

    override fun getCount(): Int = events.size

    override fun getViewAt(position: Int): RemoteViews {
        try {
            val event = events[position]
            val views = RemoteViews(context.packageName, R.layout.widget_event_list_item)
            
            val apiFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            val eventTime = try { apiFormat.parse(event.date_at)?.time ?: 0L } catch(e: Exception) { 0L }
            val isPast = eventTime < System.currentTimeMillis()

            val datetimeString = com.lito.planify.util.DateTimeUtils.formatEventDate(event.date_at)
            val relativeLabel = com.lito.planify.util.DateTimeUtils.getRelativeTime(context, event.date_at)

            views.setTextViewText(R.id.event_title, event.title)
            views.setTextViewText(R.id.event_datetime, datetimeString)

            if (event.alarm != null) {
                views.setViewVisibility(R.id.event_alarm_icon, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.event_alarm_icon, android.view.View.GONE)
            }

            if (isPast) {
                // Dimmed style for past events
                views.setTextColor(R.id.event_title, android.graphics.Color.parseColor("#9E9E9E"))
                views.setTextColor(R.id.event_datetime, android.graphics.Color.parseColor("#BDBDBD"))
                views.setInt(R.id.event_color_line, "setBackgroundColor", android.graphics.Color.parseColor("#E0E0E0"))
                views.setViewVisibility(R.id.badge_container, android.view.View.GONE)
            } else {
                // Normal style for upcoming events
                views.setTextColor(R.id.event_title, android.graphics.Color.parseColor("#1D1B20"))
                views.setTextColor(R.id.event_datetime, android.graphics.Color.parseColor("#757575"))
                
                val colorRes = try { 
                    android.graphics.Color.parseColor(event.calendar_color ?: "#6923E2") 
                } catch(e: Exception) { 
                    android.graphics.Color.parseColor("#6923E2") 
                }
                views.setInt(R.id.event_color_line, "setBackgroundColor", colorRes)

                if (relativeLabel != null && relativeLabel.isNotBlank()) {
                    views.setViewVisibility(R.id.badge_container, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.event_relative_label, relativeLabel.uppercase(java.util.Locale.getDefault()))
                } else {
                    views.setViewVisibility(R.id.badge_container, android.view.View.GONE)
                }
            }

            val fillInIntent = Intent().apply {
                putExtra("calendarId", 0)
                putExtra("calendarName", "Global")
            }
            views.setOnClickFillInIntent(R.id.widget_item_root, fillInIntent)

            return views
        } catch (e: Exception) {
            e.printStackTrace()
            return RemoteViews(context.packageName, R.layout.widget_event_list_item)
        }
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
