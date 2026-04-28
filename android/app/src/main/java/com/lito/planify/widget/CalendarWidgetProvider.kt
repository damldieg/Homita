package com.lito.planify.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.lito.planify.MainActivity
import com.lito.planify.R
import kotlinx.coroutines.flow.firstOrNull
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.*

class CalendarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.lito.planify.widget.ACTION_CLEAR_CACHE") {
            WidgetViewsFactory.clearCache(context)
            
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = android.content.ComponentName(context, CalendarWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            for (id in appWidgetIds) {
                appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_event_list)
            }
        } else if (intent.action == "com.lito.planify.widget.ACTION_REDRAW_HEADER") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = android.content.ComponentName(context, CalendarWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            for (id in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, id)
            }
        }
    }

    companion object {

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_calendar)
            
            // General Click -> Global Events
            val globalIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("calendarId", 0)
                putExtra("calendarName", "Global")
                data = Uri.parse("calendar://global_events")
            }
            val pendingGlobal = PendingIntent.getActivity(context, 0, globalIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_header_days_container, pendingGlobal)

            val today = LocalDate.now()
            val eventCounts = WidgetViewsFactory.getEventCountsPerDay(context)

            views.removeAllViews(R.id.widget_header_days_container)
            
            for (i in 0..6) {
                val date = today.plusDays(i.toLong())
                val dayNameStr = date.format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault())).replaceFirstChar { it.uppercaseChar() }
                val dayNumber = date.dayOfMonth.toString()
                
                val dayView = RemoteViews(context.packageName, R.layout.widget_day_item_header)
                dayView.setTextViewText(R.id.day_name, dayNameStr)
                dayView.setTextViewText(R.id.day_number, dayNumber)
                
                val isToday = date == today
                if (isToday) {
                    dayView.setTextColor(R.id.day_name, android.graphics.Color.parseColor("#0B57D0")) // Light blue/primary
                    dayView.setTextColor(R.id.day_number, android.graphics.Color.parseColor("#1D1B20")) // Dark text for soft bg
                    dayView.setInt(R.id.day_container, "setBackgroundResource", R.drawable.widget_active_day_bg)
                } else {
                    dayView.setTextColor(R.id.day_name, android.graphics.Color.parseColor("#5A5853"))
                    dayView.setTextColor(R.id.day_number, android.graphics.Color.parseColor("#1D1B20"))
                    dayView.setInt(R.id.day_container, "setBackgroundResource", 0) 
                }

                // Count Badge
                val dayInfo = eventCounts[date.toString()]
                if (dayInfo != null && dayInfo.first > 0) {
                    dayView.setViewVisibility(R.id.day_badge_container, android.view.View.VISIBLE)
                    dayView.setTextViewText(R.id.day_badge_text, dayInfo.first.toString())
                    
                    // Rojo con un poco de transparencia: ~85% opacity (D9)
                    val badgeColor = android.graphics.Color.parseColor("#D9D32F2F") 
                    dayView.setInt(R.id.day_badge_bg, "setColorFilter", badgeColor)
                } else {
                    dayView.setViewVisibility(R.id.day_badge_container, android.view.View.INVISIBLE)
                }

                dayView.setOnClickPendingIntent(R.id.day_container, pendingGlobal)

                views.addView(R.id.widget_header_days_container, dayView)
            }

            // RemoteViews Service attached to ListView
            val serviceIntent = Intent(context, WidgetRemoteViewsService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_event_list, serviceIntent)
            views.setEmptyView(R.id.widget_event_list, R.id.widget_empty_view)

            val clickIntentTemplate = Intent(context, MainActivity::class.java).apply {
                data = Uri.parse("calendar://open_main_from_list")
            }
            val clickPendingIntentTemplate = PendingIntent.getActivity(context, 0, clickIntentTemplate, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            views.setPendingIntentTemplate(R.id.widget_event_list, clickPendingIntentTemplate)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
