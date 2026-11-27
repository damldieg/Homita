package com.dld.homita.dashboard.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Cola de «hecho» en disco, estado visible de una tarea y filtro por persona (dashboard-marcar-hecho). */
class CompletionTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun completion(id: Int, done: Boolean, key: String) = Completion(id, done, key, 1_000L)
    private fun task(id: Int, done: Boolean, persons: List<Person>? = null) =
        Task(id, 1, "Compra", null, "T$id", id, if (done) "2026-11-27 10:00:00" else null, "media", null, persons)

    @Test
    fun laColaGuardaEnOrdenYSobreviveAlReinicio() {
        val file = folder.newFile("completions.json")
        val queue = CompletionQueue(file)
        queue.add(completion(1, true, "k1"))
        queue.add(completion(2, false, "k2"))
        assertEquals(listOf("k1", "k2"), CompletionQueue(file).all().map { it.requestId })
        queue.remove("k1")
        assertEquals(listOf("k2"), CompletionQueue(file).all().map { it.requestId })
    }

    @Test
    fun unaColaSinArchivoEstaVacia() {
        assertTrue(CompletionQueue(folder.root.resolve("no-existe.json")).all().isEmpty())
    }

    @Test
    fun elToquePendienteOLaColaMandanSobreElServidor() {
        val server = task(1, done = false)
        assertFalse(server.isDone(null))
        assertTrue(server.isDone(completion(1, true, "k")))
        assertFalse(task(2, done = true).isDone(completion(2, false, "k")))
        assertTrue(task(3, done = true).isDone(null))
    }

    @Test
    fun elFiltroPorPersonaDejaLoSuyoEnHoyYTareas() {
        val lucia = Person(1, "Lucía", "#AA00FF")
        val pablo = Person(2, "Pablo", "#FF6600")
        val content = Content(
            events = listOf(
                Event(1, 1, "Familia", "#000000", "Dentista", "2026-11-27 17:00:00", persons = listOf(lucia)),
                Event(2, 1, "Familia", "#000000", "Partido", "2026-11-27 18:00:00", persons = listOf(pablo)),
            ),
            sessions = emptyList(),
            tasks = listOf(task(1, false, listOf(lucia)), task(2, false, listOf(pablo)), task(3, false, null)),
        )
        val filtered = PersonFilter.content(content, lucia.id)!!
        assertEquals(listOf("Dentista"), filtered.events.map { it.title })
        assertEquals(listOf(1), filtered.tasks.map { it.id })
        assertEquals(content, PersonFilter.content(content, null))
    }
}
