package com.dld.homita.dashboard.data

/**
 * Último resultado de cada dato remoto (Ajustes → Diagnóstico, N6): cuándo fue la última descarga buena y el último
 * error (p. ej. «HTTP 403» del menú de hoy). En memoria: se empieza de cero al reiniciar el marco.
 */
class Diagnostics(private val nowMillis: () -> Long = System::currentTimeMillis) {
    data class Entry(val lastOkAt: Long?, val lastError: String?, val lastErrorAt: Long?)

    private val entries = LinkedHashMap<String, Entry>()

    @Synchronized
    fun record(endpoint: String, result: Result<*>) {
        val previous = entries[endpoint]
        val error = result.exceptionOrNull()
        entries[endpoint] = if (error == null) {
            Entry(lastOkAt = nowMillis(), lastError = null, lastErrorAt = previous?.lastErrorAt)
        } else {
            Entry(lastOkAt = previous?.lastOkAt, lastError = describe(error), lastErrorAt = nowMillis())
        }
    }

    @Synchronized
    fun snapshot(): Map<String, Entry> = LinkedHashMap(entries)

    companion object {
        /** Texto corto del error: el código HTTP si lo hay; si no, el tipo de error. */
        fun describe(error: Throwable): String = when (error) {
            is HttpError -> "HTTP ${error.code}"
            else -> error::class.java.simpleName.ifEmpty { "Error" }
        }
    }
}
