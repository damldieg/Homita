package com.lito.planify.util

import android.content.Context
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CrashReporter(private val context: Context) : Thread.UncaughtExceptionHandler {
    private val defaultHandler: Thread.UncaughtExceptionHandler? = Thread.getDefaultUncaughtExceptionHandler()

    override fun uncaughtException(t: Thread, e: Throwable) {
        saveCrashReport(e)
        defaultHandler?.uncaughtException(t, e)
    }

    private fun saveCrashReport(e: Throwable) {
        try {
            val file = File(context.filesDir, "crash_dump.txt")
            val writer = PrintWriter(FileWriter(file, true))
            
            val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            writer.println("--- CRASH REPORT: ${dateFormat.format(Date())} ---")
            e.printStackTrace(writer)
            writer.println("---------------------------------------------------\n")
            writer.flush()
            writer.close()
        } catch (ex: Exception) {
            // No podemos hacer nada si falla el reporte del propio crash
        }
    }

    companion object {
        fun init(context: Context) {
            val currentHandler = Thread.getDefaultUncaughtExceptionHandler()
            if (currentHandler !is CrashReporter) {
                Thread.setDefaultUncaughtExceptionHandler(CrashReporter(context))
            }
        }
        
        fun hasCrashDump(context: Context): Boolean {
            return File(context.filesDir, "crash_dump.txt").exists()
        }
        
        fun getCrashDumpDate(context: Context): String {
            val file = File(context.filesDir, "crash_dump.txt")
            if (file.exists()) {
                val lastMod = file.lastModified()
                val format = SimpleDateFormat("yyyy-MM-dd · HH:mm", Locale.getDefault())
                return format.format(Date(lastMod))
            }
            return ""
        }
        
        fun readCrashDump(context: Context): String {
            val file = File(context.filesDir, "crash_dump.txt")
            return if (file.exists()) file.readText() else ""
        }
        
        fun clearCrashDump(context: Context) {
            val file = File(context.filesDir, "crash_dump.txt")
            if (file.exists()) {
                file.delete()
            }
        }
    }
}