package com.lito.planify.data.api

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST

interface ApiService {

    @GET("config")
    suspend fun getConfig(): Response<ConfigResponse>

    @POST("user/create")
    suspend fun register(@Body request: RegisterRequest): Response<UserResponse>

    @POST("user/auth")
    suspend fun authenticate(@Body request: AuthRequest): Response<UserResponse>

    @PATCH("user/update")
    suspend fun updateProfile(@Body request: UpdateProfileRequest): Response<UserResponse>

    // Calendars
    @GET("calendar")
    suspend fun getCalendars(): Response<List<CalendarResponse>>

    @GET("calendar/detail")
    suspend fun getCalendarDetail(@retrofit2.http.Query("id") id: Int): Response<CalendarResponse>

    @POST("calendar/create")
    suspend fun createCalendar(@Body request: CreateCalendarRequest): Response<CalendarResponse>

    @PATCH("calendar/update")
    suspend fun updateCalendar(@Body request: UpdateCalendarRequest): Response<CalendarResponse>

    @retrofit2.http.HTTP(method = "DELETE", path = "calendar/delete", hasBody = true)
    suspend fun deleteCalendar(@Body request: DeleteRequest): Response<Map<String, Any>>

    @POST("calendar/user")
    suspend fun createCalendarUser(@Body request: CreateCalendarUserRequest): Response<CalendarResponse>

    @GET("calendar/user")
    suspend fun getCalendarUsers(@retrofit2.http.Query("calendar_id") calendarId: Int): Response<List<CalendarUserResponse>>

    @retrofit2.http.HTTP(method = "DELETE", path = "calendar/user", hasBody = true)
    suspend fun removeCalendarUser(@Body request: DeleteCalendarUserRequest): Response<Map<String, Any>>

    // Events
    @GET("event")
    suspend fun getEvents(
        @retrofit2.http.Query("calendar_id") calendarId: Int? = null,
        @retrofit2.http.Query("q") search: String? = null,
        @retrofit2.http.Query("start_date") startDate: String? = null,
        @retrofit2.http.Query("end_date") endDate: String? = null,
        @retrofit2.http.Query("limit") limit: Int? = null,
        @retrofit2.http.Query("order_mode") orderMode: String? = null,
        @retrofit2.http.Query("widget") widget: Boolean? = null
    ): Response<List<EventResponse>>

    @GET("event/detail")
    suspend fun getEventDetail(@retrofit2.http.Query("id") id: Int): Response<EventResponse>

    @POST("event/create")
    suspend fun createEvent(@Body request: CreateEventRequest): Response<EventResponse>

    @PATCH("event/update")
    suspend fun updateEvent(@Body request: UpdateEventRequest): Response<EventResponse>

    @PATCH("event/alarm")
    suspend fun setEventAlarm(@Body request: SetEventAlarmRequest): Response<EventResponse>

    @retrofit2.http.HTTP(method = "DELETE", path = "event/delete", hasBody = true)
    suspend fun deleteEvent(@Body request: DeleteRequest): Response<Map<String, Any>>

    // --- Task Lists ---
    @GET("task-list")
    suspend fun getTaskLists(): Response<List<TaskListResponse>>

    @POST("task-list/create")
    suspend fun createTaskList(@Body request: CreateTaskListRequest): Response<TaskListResponse>

    @PATCH("task-list/update")
    suspend fun updateTaskList(@Body request: UpdateTaskListRequest): Response<TaskListResponse>

    @retrofit2.http.HTTP(method = "DELETE", path = "task-list/delete", hasBody = true)
    suspend fun deleteTaskList(@Body request: DeleteRequest): Response<Map<String, Any>>

    @POST("task-list/user")
    suspend fun createTaskListUser(@Body request: CreateTaskListUserRequest): Response<Unit>

    @GET("task-list/user")
    suspend fun getTaskListUsers(@retrofit2.http.Query("task_list_id") taskListId: Int): Response<List<TaskListUserResponse>>

    @retrofit2.http.HTTP(method = "DELETE", path = "task-list/user", hasBody = true)
    suspend fun removeTaskListUser(@Body request: DeleteTaskListUserRequest): Response<Map<String, Any>>

    // --- Tasks ---
    @GET("task")
    suspend fun getTasks(
        @retrofit2.http.Query("task_list_id") taskListId: Int? = null,
        @retrofit2.http.Query("q") search: String? = null,
        @retrofit2.http.Query("widget") widget: Boolean? = null
    ): Response<List<TaskResponse>>

    @POST("task/create")
    suspend fun createTask(@Body request: CreateTaskRequest): Response<TaskResponse>

    @PATCH("task/update")
    suspend fun updateTask(@Body request: UpdateTaskRequest): Response<TaskResponse>

    @PATCH("task/complete")
    suspend fun completeTask(@Body request: CompleteTaskRequest): Response<TaskResponse>

    @PATCH("task/order")
    suspend fun orderTask(@Body request: OrderTaskRequest): Response<TaskResponse>

    @retrofit2.http.HTTP(method = "DELETE", path = "task/delete", hasBody = true)
    suspend fun deleteTask(@Body request: DeleteRequest): Response<Map<String, Any>>
}
