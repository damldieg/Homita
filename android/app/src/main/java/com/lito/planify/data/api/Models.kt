package com.lito.planify.data.api

data class ConfigResponse(
    val allow_registration: Boolean
)

data class UserResponse(
    val id: Int,
    val name: String,
    val email: String,
    val token: String?,
    val created_at: String,
    val updated_at: String
)

data class RegisterRequest(
    val name: String,
    val email: String,
    val password: String? = null
)

data class AuthRequest(
    val email: String,
    val password: String? = null
)

data class UpdateProfileRequest(
    val name: String,
    val email: String,
    val password: String? = null
)

data class CalendarResponse(
    val id: Int,
    val name: String,
    val color: String,
    val token: String,
    val created_at: String,
    val updated_at: String,
    val widget: Boolean? = true,
    val upcoming_event_count: Int? = 0
)

data class CreateCalendarRequest(
    val name: String,
    val color: String? = null,
    val widget: Boolean? = true
)

data class UpdateCalendarRequest(
    val id: Int,
    val name: String,
    val color: String,
    val widget: Boolean? = true
)

data class DeleteRequest(
    val id: Int
)

data class CreateCalendarUserRequest(
    val calendar_id: Int,
    val email: String
)

data class CalendarUserResponse(
    val cu_id: Int,
    val user_id: Int,
    val name: String,
    val email: String,
    val role: String
)

data class DeleteCalendarUserRequest(
    val calendar_id: Int,
    val user_id: Int
)

data class EventResponse(
    val id: Int,
    val calendar_id: Int,
    val calendar_color: String?,
    val calendar_name: String?,
    val title: String,
    val date_at: String,
    val alarm: Int? = null,
    val created_at: String,
    val updated_at: String
)

data class CreateEventRequest(
    val calendar_id: Int,
    val text: String? = null,
    val title: String? = null,
    val date_at: String? = null,
    val alarm: Int? = null
)

data class UpdateEventRequest(
    val id: Int,
    val title: String,
    val date_at: String,
    val alarm: Int? = null
)

data class SetEventAlarmRequest(
    val event_id: Int,
    val alarm: Int?
)

// --- TASK LISTS & TASKS MODELS ---

data class TaskListResponse(
    val id: Int,
    val name: String,
    val color: String,
    val token: String,
    val sort: String,
    val created_at: String,
    val updated_at: String,
    val widget: Boolean? = true,
    val pending_task_count: Int? = 0
)

data class CreateTaskListRequest(
    val name: String,
    val color: String? = null,
    val sort: String? = null,
    val widget: Boolean? = true
)

data class UpdateTaskListRequest(
    val id: Int,
    val name: String,
    val color: String,
    val sort: String,
    val widget: Boolean? = true
)

data class TaskListUserResponse(
    val cu_id: Int,
    val user_id: Int,
    val name: String,
    val email: String,
    val role: String
)

data class CreateTaskListUserRequest(
    val task_list_id: Int,
    val email: String
)

data class DeleteTaskListUserRequest(
    val task_list_id: Int,
    val user_id: Int
)

data class TaskResponse(
    val id: Int,
    val task_list_id: Int,
    val task_list_color: String?,
    val task_list_name: String?,
    val title: String,
    val order: Int,
    val completed_at: String?,
    val created_at: String,
    val updated_at: String
)

data class CreateTaskRequest(
    val task_list_id: Int,
    val title: String
)

data class UpdateTaskRequest(
    val id: Int,
    val title: String
)

data class CompleteTaskRequest(
    val id: Int,
    val completed: Boolean
)

data class OrderTaskRequest(
    val id: Int,
    val position: Int
)