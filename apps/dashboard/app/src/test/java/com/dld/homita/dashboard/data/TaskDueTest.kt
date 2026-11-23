package com.dld.homita.dashboard.data

import com.dld.homita.dashboard.data.Task
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Fecha límite de tareas (0041): la API da UTC y la fila muestra la hora local. */
class TaskDueTest {
    @Test
    fun `convierte UTC a la zona indicada`() {
        assertEquals(
            LocalDateTime.of(2026, 12, 3, 18, 0),
            TaskDue.local("2026-12-03 18:00:00", ZoneId.of("UTC")),
        )
        // Madrid en diciembre es UTC+1.
        assertEquals(
            LocalDateTime.of(2026, 12, 3, 19, 0),
            TaskDue.local("2026-12-03 18:00:00", ZoneId.of("Europe/Madrid")),
        )
    }

    @Test
    fun `sin fecha o ilegible no hay etiqueta`() {
        assertNull(TaskDue.local(null, ZoneId.of("UTC")))
        assertNull(TaskDue.local("", ZoneId.of("UTC")))
        assertNull(TaskDue.local("mañana", ZoneId.of("UTC")))
        assertNull(TaskDue.label("2026-13-01 10:00:00", ZoneId.of("UTC")))
    }

    @Test
    fun `la etiqueta usa dia y mes con hora`() {
        assertEquals("03/12 19:00", TaskDue.label("2026-12-03 18:00:00", ZoneId.of("Europe/Madrid")))
    }

    private fun task(id: Int, due: String?, priority: String = "alta", done: String? = null) = Task(
        id = id, task_list_id = 1, task_list_name = "Compra", task_list_color = null, title = "Tarea $id",
        order = id, completed_at = done, priority = priority, due_at = due,
    )

    private val utc = ZoneId.of("UTC")
    private val now = LocalDateTime.of(2026, 12, 1, 10, 0)

    @Test
    fun `el banner es la alta pendiente futura que vence antes`() {
        val tasks = listOf(
            task(1, "2026-12-02 10:00:00"),
            task(2, "2026-12-01 12:00:00"),
            task(3, "2026-12-01 11:00:00", priority = "media"),
            task(4, "2026-12-01 09:00:00"),
            task(5, "2026-12-01 10:30:00", done = "2026-12-01 09:00:00"),
            task(6, null),
        )
        val banner = TaskDue.banner(tasks, now, emptySet(), utc)
        assertEquals(2, banner?.task?.id)
        assertEquals(LocalDateTime.of(2026, 12, 1, 12, 0), banner?.due)
    }

    @Test
    fun `cerrado en la sesion no vuelve y sin candidatos no hay banner`() {
        val tasks = listOf(task(1, "2026-12-01 12:00:00"))
        assertNull(TaskDue.banner(tasks, now, setOf(1), utc))
        assertNull(TaskDue.banner(emptyList(), now, emptySet(), utc))
    }
}
