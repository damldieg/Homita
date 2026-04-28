package com.lito.planify.util

import android.text.format.DateUtils
import java.text.SimpleDateFormat
import java.util.*

object DateTimeUtils {
    private val apiFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    fun formatEventDate(dateStr: String): String {
        return try {
            val date = apiFormat.parse(dateStr) ?: return dateStr
            // "EEE d MMM" yields "Thu 19 Apr" which adapts to the user's locale.
            val dateFormat = SimpleDateFormat("EEE d MMM", Locale.getDefault())
            val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
            "${dateFormat.format(date)} · ${timeFormat.format(date)}".uppercase()
        } catch (e: Exception) {
            dateStr
        }
    }

    fun getRelativeTime(context: android.content.Context, dateStr: String): String? {
        return try {
            val eventDate = apiFormat.parse(dateStr) ?: return null
            val now = System.currentTimeMillis()
            val time = eventDate.time
            
            val diffMs = time - now
            val isPast = diffMs < 0
            val absDiffMs = Math.abs(diffMs)
            
            val diffMins = java.util.concurrent.TimeUnit.MILLISECONDS.toMinutes(absDiffMs)
            val diffHours = java.util.concurrent.TimeUnit.MILLISECONDS.toHours(absDiffMs)

            if (diffMins < 1) return context.getString(com.lito.planify.R.string.relative_now)

            val unitMonth = context.getString(com.lito.planify.R.string.relative_month_short)
            val unitDay = context.getString(com.lito.planify.R.string.relative_day_short)
            val unitHour = context.getString(com.lito.planify.R.string.relative_hour_short)
            val unitMin = context.getString(com.lito.planify.R.string.relative_minute_short)

            // 1. Calcular días naturales (calendar days) para etiquetas de un solo elemento (> 2 días)
            val calNow = Calendar.getInstance().apply { timeInMillis = now }
            calNow.set(Calendar.HOUR_OF_DAY, 0)
            calNow.set(Calendar.MINUTE, 0)
            calNow.set(Calendar.SECOND, 0)
            calNow.set(Calendar.MILLISECOND, 0)

            val calEvent = Calendar.getInstance().apply { timeInMillis = time }
            calEvent.set(Calendar.HOUR_OF_DAY, 0)
            calEvent.set(Calendar.MINUTE, 0)
            calEvent.set(Calendar.SECOND, 0)
            calEvent.set(Calendar.MILLISECOND, 0)

            val diffCalendarMs = Math.abs(calEvent.timeInMillis - calNow.timeInMillis)
            val calendarDays = java.util.concurrent.TimeUnit.MILLISECONDS.toDays(diffCalendarMs).toInt()

            val timeLabel = when {
                // Para más de un mes o más de 2 días naturales, usamos días de calendario (referencia 00:00)
                calendarDays >= 30 -> {
                    val months = calendarDays / 30
                    val remDays = calendarDays % 30
                    if (remDays > 0) "${months}$unitMonth ${remDays}$unitDay" else "${months}$unitMonth"
                }
                calendarDays > 2 -> {
                    "${calendarDays}$unitDay"
                }
                // Para hoy, mañana o pasado (hasta 2 días), usamos tiempo absoluto (referencia AHORA) para mostrar 2 elementos
                else -> {
                    if (diffHours > 0) {
                        val mins = (diffMins % 60)
                        if (calendarDays > 0) {
                            // Si es mañana/pasado pero entra en el rango de 2 elementos, mostramos Días y Horas absolutos
                            val daysAbs = diffHours / 24
                            val hoursAbs = diffHours % 24
                            if (daysAbs > 0) {
                                if (hoursAbs > 0) "${daysAbs}$unitDay ${hoursAbs}$unitHour" else "${daysAbs}$unitDay"
                            } else {
                                if (hoursAbs > 0) "${hoursAbs}$unitHour ${mins}$unitMin" else "${hoursAbs}$unitHour"
                            }
                        } else {
                            // Es hoy
                            if (mins > 0) "${diffHours}$unitHour ${mins}$unitMin" else "${diffHours}$unitHour"
                        }
                    } else {
                        "${diffMins}$unitMin"
                    }
                }
            }

            if (isPast) {
                context.getString(com.lito.planify.R.string.relative_ago, timeLabel)
            } else {
                context.getString(com.lito.planify.R.string.relative_in, timeLabel)
            }
        } catch (e: Exception) {
            null
        }
    }
}
