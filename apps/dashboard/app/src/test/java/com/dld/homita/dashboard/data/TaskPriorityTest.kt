package com.dld.homita.dashboard.data

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Prioridad de tarea (0037): parseo tolerante, orden y filtro en cliente y caché antigua sin la clave. */
class TaskPriorityTest {
    private fun task(id: Int, priority: String?, order: Int, completed: Boolean = false) =
        Task(id, 2, "Compra", "#6923E2", "T$id", order, if (completed) "2026-11-20 10:00:00" else null, priority)

    @Test
    fun absentOrUnknownPriorityIsMedia() {
        assertEquals(TaskPriority.MEDIA, TaskPriority.from(null))
        assertEquals(TaskPriority.MEDIA, TaskPriority.from("urgentisima"))
        assertEquals(TaskPriority.MEDIA, TaskPriority.from("ALTA"))
        assertEquals(TaskPriority.ALTA, TaskPriority.from("alta"))
        assertEquals(TaskPriority.BAJA, TaskPriority.from("baja"))
        assertEquals(listOf(1, 2, 3), TaskPriority.entries.map { it.rank })
    }

    @Test
    fun oldDiskCacheWithoutPriorityDecodesAsMedia() {
        // JSON tal como lo guardaba la caché antes de 0037: sin la clave priority.
        val json = """[{"id":1,"task_list_id":2,"task_list_name":"Compra","task_list_color":"#6923E2","title":"Pan","order":1,"completed_at":null}]"""
        val tasks: List<Task> = Gson().fromJson(json, object : TypeToken<List<Task>>() {}.type)
        assertNull(tasks[0].priority)
        assertEquals(TaskPriority.MEDIA, tasks[0].priorityValue)
        val fresh: List<Task> = Gson().fromJson(json.replace("\"completed_at\":null", "\"completed_at\":null,\"priority\":\"alta\""), object : TypeToken<List<Task>>() {}.type)
        assertEquals(TaskPriority.ALTA, fresh[0].priorityValue)
    }

    @Test
    fun defaultsKeepServerOrderWithoutFilter() {
        val tasks = listOf(task(1, "baja", 1), task(2, "alta", 2), task(3, null, 3))
        assertEquals(TaskSort.LIST, TaskSort.from(null))
        assertEquals(TaskSort.LIST, TaskSort.from("desconocido"))
        assertEquals(tasks, TaskPriorityView.apply(tasks, TaskSort.LIST, null))
    }

    @Test
    fun prioritySortTieBreaksByOrderThenIdAndCompletedLast() {
        val tasks = listOf(
            task(1, "baja", 1), task(2, "alta", 3), task(3, null, 2), task(4, "alta", 1),
            task(5, "alta", 1, completed = true), task(6, "media", 4), task(7, "alta", 3)
        )
        assertEquals(listOf(4, 2, 7, 3, 6, 1, 5), TaskPriorityView.sortTasks(tasks, TaskSort.PRIORITY).map { it.id })
    }

    @Test
    fun filterKeepsOnlyThatPriority() {
        val tasks = listOf(task(1, "baja", 1), task(2, "alta", 2), task(3, null, 3))
        assertEquals(listOf(3), TaskPriorityView.filterTasks(tasks, TaskPriority.MEDIA).map { it.id })
        assertEquals(listOf(2), TaskPriorityView.apply(tasks, TaskSort.PRIORITY, TaskPriority.ALTA).map { it.id })
        assertEquals(tasks, TaskPriorityView.filterTasks(tasks, null))
    }
}
