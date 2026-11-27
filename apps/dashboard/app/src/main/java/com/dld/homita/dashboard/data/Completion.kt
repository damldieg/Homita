package com.dld.homita.dashboard.data

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * Un toque de «hecho» pendiente de enviar (dashboard-marcar-hecho). [requestId] es la clave de cliente que hace el
 * reenvío idempotente en el servidor (0050).
 */
data class Completion(val taskId: Int, val completed: Boolean, val requestId: String, val createdAt: Long)

/**
 * Cola en disco de los toques que salieron de la ventana de «Deshacer» y aún no se han enviado. Sobrevive a reinicios
 * y a la falta de red; se vacía en orden de llegada. Un fallo de escritura no rompe la pantalla: la cola queda como estaba.
 */
class CompletionQueue(private val file: File) {
    private val gson = Gson()
    private val listType = object : TypeToken<List<Completion>>() {}.type

    @Synchronized
    fun all(): List<Completion> = runCatching {
        if (file.exists()) gson.fromJson<List<Completion>>(file.readText(), listType).orEmpty() else emptyList()
    }.getOrDefault(emptyList())

    @Synchronized
    fun add(completion: Completion) = write(all() + completion)

    @Synchronized
    fun remove(requestId: String) = write(all().filterNot { it.requestId == requestId })

    /** Vacía la cola (cierre de sesión explícito o desvinculación: los toques eran de otra sesión). */
    @Synchronized
    fun clear() = write(emptyList())

    private fun write(items: List<Completion>) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(gson.toJson(items))
            tmp.renameTo(file)
        }
    }
}

/**
 * Qué hacer con un toque tras intentar enviarlo (R1-01, R2-01). Un error permanente (la tarea ya no existe o está oculta,
 * la pantalla no tiene permiso, la clave no vale, un 500 de la RPC) quita el toque y avisa, para que no bloquee los
 * siguientes. Sin red, 408, 429, 502-504 (pasarela) u otro fallo transitorio se queda en la cola para el próximo intento.
 */
enum class CompletionOutcome { Sent, Retry, Discard, Unauthorized }

fun completionOutcome(error: Throwable?): CompletionOutcome = when {
    error == null -> CompletionOutcome.Sent
    error is SessionExpired || error.isUnauthorized -> CompletionOutcome.Unauthorized
    error is HttpError && (error.code == 408 || error.code == 429 || error.code in 502..504) -> CompletionOutcome.Retry
    error is HttpError -> CompletionOutcome.Discard
    else -> CompletionOutcome.Retry
}

/** Estado visible de una tarea: el toque pendiente (ventana o cola) manda sobre lo que dice el servidor. */
fun Task.isDone(pending: Completion?): Boolean = pending?.completed ?: (completed_at != null)

/** Filtro por persona (U4): lo que tiene asignado esa persona, en Hoy, Calendario y Tareas. */
object PersonFilter {
    fun content(content: Content?, personId: Int?): Content? {
        if (content == null || personId == null) return content
        return Content(
            events = content.events.filter { mine(it.persons, personId) },
            sessions = content.sessions.filter { mine(it.persons, personId) },
            tasks = content.tasks.filter { mine(it.persons, personId) }
        )
    }

    fun week(week: Week, personId: Int): Week =
        Week(week.events.filter { mine(it.persons, personId) }, week.sessions.filter { mine(it.persons, personId) })

    fun mine(persons: List<Person>?, personId: Int): Boolean = persons?.any { it.id == personId } == true
}
