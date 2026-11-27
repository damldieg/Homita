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
    fun `el aviso es la alta pendiente que vence antes, incluidas las vencidas`() {
        val tasks = listOf(
            task(1, "2026-12-02 10:00:00"),
            task(2, "2026-12-01 12:00:00"),
            task(3, "2026-12-01 11:00:00", priority = "media"),
            task(4, "2026-12-01 09:00:00"),
            task(5, "2026-12-01 10:30:00", done = "2026-12-01 09:00:00"),
            task(6, null),
        )
        val banner = TaskDue.banner(tasks, now, emptySet(), utc)
        // La 4 ya venció (09:00): N1, sigue en el aviso hasta completarla
        assertEquals(4, banner?.task?.id)
        assertEquals(LocalDateTime.of(2026, 12, 1, 9, 0), banner?.due)
    }

    @Test
    fun `solo avisa de lo que vence en menos de 48 horas`() {
        val lejana = listOf(task(1, "2026-12-03 10:01:00"))
        assertNull(TaskDue.banner(lejana, now, emptySet(), utc))
        val dentro = listOf(task(2, "2026-12-03 09:59:00"))
        assertEquals(2, TaskDue.banner(dentro, now, emptySet(), utc)?.task?.id)
    }

    @Test
    fun `cerrado no vuelve, la clave cambia con la fecha y sin candidatos no hay aviso`() {
        val tasks = listOf(task(1, "2026-12-01 12:00:00"))
        assertNull(TaskDue.banner(tasks, now, setOf(TaskDue.key(tasks[0])), utc))
        // Si cambia la fecha, la clave ya no coincide: vuelve a avisar
        assertEquals(1, TaskDue.banner(tasks, now, setOf("1@2026-11-30 10:00:00"), utc)?.task?.id)
        assertNull(TaskDue.banner(emptyList(), now, emptySet(), utc))
    }

    @Test
    fun `la fecha relativa dice hoy, manana o el dia`() {
        assertEquals("Hoy 12:00", TaskDue.whenText(LocalDateTime.of(2026, 12, 1, 12, 0), now))
        assertEquals("Mañana 09:00", TaskDue.whenText(LocalDateTime.of(2026, 12, 2, 9, 0), now))
        assertEquals("jue 3 dic 19:00", TaskDue.whenText(LocalDateTime.of(2026, 12, 3, 19, 0), now))
    }

    @Test
    fun `lo vencido dice cuanto hace`() {
        assertEquals("Vencida ahora", TaskDue.whenText(now.minusSeconds(20), now))
        assertEquals("Vencida hace 45 min", TaskDue.whenText(now.minusMinutes(45), now))
        assertEquals("Vencida hace 2 h", TaskDue.whenText(now.minusHours(2), now))
        assertEquals("Vencida hace 3 d", TaskDue.whenText(now.minusDays(3), now))
    }

    @Test
    fun `banners lista todos los avisos abiertos, del que vence antes al ultimo`() {
        val tasks = listOf(
            task(1, "2026-12-01 12:00:00"),
            task(2, "2026-12-01 09:00:00"),
            task(3, "2026-12-01 11:00:00", priority = "media"),
            task(4, "2026-12-03 09:00:00"),
        )
        assertEquals(listOf(2, 1, 4), TaskDue.banners(tasks, now, emptySet(), utc).map { it.task.id })
        assertEquals(listOf(1, 4), TaskDue.banners(tasks, now, setOf(TaskDue.key(tasks[1])), utc).map { it.task.id })
    }
}
