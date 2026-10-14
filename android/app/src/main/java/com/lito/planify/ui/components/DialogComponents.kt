package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.lito.planify.R
import com.lito.planify.data.api.CalendarResponse
import com.lito.planify.data.api.CalendarUserResponse
import com.lito.planify.data.api.CreateRoutineRequest
import com.lito.planify.data.api.DashboardConfigResponse
import com.lito.planify.data.api.EventResponse
import com.lito.planify.data.api.PersonResponse
import com.lito.planify.data.api.RoutineResponse
import com.lito.planify.data.api.TaskListResponse
import com.lito.planify.data.api.TaskListUserResponse
import com.lito.planify.ui.theme.*
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private val apiDateTimeFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
private val timeFormat = DateTimeFormatter.ofPattern("HH:mm")

private fun formatDate(date: LocalDate, pattern: String = "EEE d MMM yyyy"): String =
    date.format(DateTimeFormatter.ofPattern(pattern, Locale.getDefault()))
        .replace(".", "")
        .replaceFirstChar { it.uppercaseChar() }

private fun showDatePicker(context: android.content.Context, date: LocalDate, onDate: (LocalDate) -> Unit) {
    android.app.DatePickerDialog(
        context,
        { _, year, month, day -> onDate(LocalDate.of(year, month + 1, day)) },
        date.year, date.monthValue - 1, date.dayOfMonth
    ).show()
}

private fun showTimePicker(context: android.content.Context, time: LocalTime, onTime: (LocalTime) -> Unit) {
    android.app.TimePickerDialog(context, { _, hour, minute -> onTime(LocalTime.of(hour, minute)) }, time.hour, time.minute, true).show()
}

@Composable
fun CreateCalendarDialog(
    initialName: String = "",
    initialColor: String? = null,
    initialWidget: Boolean = true,
    users: List<CalendarUserResponse> = emptyList(),
    onInviteUser: (String) -> Unit = {},
    onRemoveUser: (Int) -> Unit = {},
    onDismiss: () -> Unit,
    onConfirm: (String, String, Boolean) -> Unit,
    onDelete: (() -> Unit)? = null,
    isEdit: Boolean = false
) {
    var name by remember { mutableStateOf(initialName) }
    var selectedColor by remember { mutableStateOf(initialColor ?: randomHueColor()) }
    var widget by remember { mutableStateOf(initialWidget) }
    var selectedTab by remember { mutableStateOf(0) }

    PlanifyFormSheet(
        title = stringResource(if (isEdit) R.string.calendars_edit else R.string.calendars_new),
        onDismiss = onDismiss,
        confirmText = if (selectedTab == 0) stringResource(if (isEdit) R.string.generic_save else R.string.generic_create) else null,
        confirmEnabled = name.isNotBlank(),
        onConfirm = { onConfirm(name.trim(), selectedColor, widget) },
        onDelete = onDelete.takeIf { isEdit }
    ) {
        if (isEdit) SettingsTabs(selectedTab) { selectedTab = it }

        if (selectedTab == 0) {
            CustomTextField(
                value = name,
                onValueChange = { name = it },
                label = stringResource(R.string.label_name),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
            )
            ColorField(selectedColor) { selectedColor = it }
            FormSwitchRow(label = stringResource(R.string.label_show_in_widget), checked = widget, onCheckedChange = { widget = it }, icon = Icons.Default.Widgets)
        } else {
            UsersSection(
                users = users.map { SharedUser(it.user_id, it.name, it.email, it.role) },
                onInviteUser = onInviteUser,
                onRemoveUser = onRemoveUser
            )
        }
    }
}

@Composable
fun CreateTaskListDialog(
    initialName: String = "",
    initialColor: String? = null,
    initialSortOrder: String = "updated_at",
    initialWidget: Boolean = true,
    users: List<TaskListUserResponse> = emptyList(),
    onInviteUser: (String) -> Unit = {},
    onRemoveUser: (Int) -> Unit = {},
    onDismiss: () -> Unit,
    onConfirm: (String, String, String, Boolean) -> Unit,
    onDelete: (() -> Unit)? = null,
    isEdit: Boolean = false
) {
    var name by remember { mutableStateOf(initialName) }
    var selectedColor by remember { mutableStateOf(initialColor ?: randomHueColor()) }
    var sortOrder by remember { mutableStateOf(initialSortOrder) }
    var widget by remember { mutableStateOf(initialWidget) }
    var selectedTab by remember { mutableStateOf(0) }

    PlanifyFormSheet(
        title = stringResource(if (isEdit) R.string.tasks_edit_list else R.string.tasks_new_list),
        onDismiss = onDismiss,
        confirmText = if (selectedTab == 0) stringResource(if (isEdit) R.string.generic_save else R.string.generic_create) else null,
        confirmEnabled = name.isNotBlank(),
        onConfirm = { onConfirm(name.trim(), selectedColor, sortOrder, widget) },
        onDelete = onDelete.takeIf { isEdit }
    ) {
        if (isEdit) SettingsTabs(selectedTab) { selectedTab = it }

        if (selectedTab == 0) {
            CustomTextField(
                value = name,
                onValueChange = { name = it },
                label = stringResource(R.string.label_name),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
            )
            FormSelectField(
                label = stringResource(R.string.label_order),
                selected = sortOrder,
                options = listOf(
                    "updated_at" to stringResource(R.string.sort_activity),
                    "title" to stringResource(R.string.sort_alphabetical),
                    "custom" to stringResource(R.string.sort_custom)
                ),
                onSelect = { sortOrder = it },
                icon = Icons.AutoMirrored.Outlined.Sort
            )
            ColorField(selectedColor) { selectedColor = it }
            FormSwitchRow(label = stringResource(R.string.label_show_in_widget), checked = widget, onCheckedChange = { widget = it }, icon = Icons.Default.Widgets)
        } else {
            UsersSection(
                users = users.map { SharedUser(it.user_id, it.name, it.email, it.role) },
                onInviteUser = onInviteUser,
                onRemoveUser = onRemoveUser
            )
        }
    }
}

@Composable
fun EventFormDialog(
    calendarId: Int,
    calendars: List<CalendarResponse> = emptyList(),
    initialEvent: EventResponse? = null,
    persons: List<PersonResponse> = emptyList(),
    onDismiss: () -> Unit,
    onConfirm: (Int, String, String, String, Int?, List<Int>) -> Unit,
    onDelete: (() -> Unit)? = null,
    isEdit: Boolean = false
) {
    val context = LocalContext.current
    val initialDateTime = remember {
        initialEvent?.date_at?.let { runCatching { LocalDateTime.parse(it, apiDateTimeFormat) }.getOrNull() }
            ?: LocalDateTime.now().withSecond(0).withNano(0)
    }

    var title by remember { mutableStateOf(initialEvent?.title ?: "") }
    var text by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(initialDateTime.toLocalDate()) }
    var time by remember { mutableStateOf(initialDateTime.toLocalTime()) }
    var alarm by remember { mutableStateOf(initialEvent?.alarm) }
    var selectedCalendarId by remember { mutableStateOf(calendarId) }
    var personIds by remember { mutableStateOf(initialEvent?.persons.orEmpty().map { it.id }) }
    var isAiMode by remember { mutableStateOf(false) }

    PlanifyFormSheet(
        title = stringResource(if (isEdit) R.string.calendars_edit_event else R.string.calendars_new_event),
        onDismiss = onDismiss,
        confirmText = stringResource(if (isEdit) R.string.generic_save else R.string.generic_create),
        confirmEnabled = if (isAiMode) text.isNotBlank() else title.isNotBlank(),
        onConfirm = { onConfirm(selectedCalendarId, title.trim(), LocalDateTime.of(date, time).format(apiDateTimeFormat), text, alarm, personIds) },
        onDelete = onDelete.takeIf { isEdit }
    ) {
        if (!isEdit && calendars.isNotEmpty()) {
            CalendarSelectField(calendars, selectedCalendarId) { selectedCalendarId = it }
        }

        if (!isEdit) {
            FormSwitchRow(label = stringResource(R.string.label_ai_assistant), checked = isAiMode, onCheckedChange = { isAiMode = it }, icon = Icons.Default.AutoAwesome)
        }

        if (isAiMode) {
            CustomTextField(
                value = text,
                onValueChange = { text = it },
                label = stringResource(R.string.label_describe_event),
                singleLine = false,
                modifier = Modifier.heightIn(min = 120.dp)
            )
        } else {
            CustomTextField(
                value = title,
                onValueChange = { title = it },
                label = stringResource(R.string.label_title),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FormPickerField(
                    label = stringResource(R.string.label_date),
                    value = formatDate(date, "d MMM yyyy"),
                    icon = Icons.Outlined.CalendarToday,
                    onClick = { showDatePicker(context, date) { date = it } },
                    modifier = Modifier.weight(1.4f)
                )
                FormPickerField(
                    label = stringResource(R.string.label_time),
                    value = time.format(timeFormat),
                    icon = Icons.Outlined.Schedule,
                    onClick = { showTimePicker(context, time) { time = it } },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        if (persons.isNotEmpty()) PersonSelector(persons, personIds, onChange = { personIds = it })
        AlarmSelectField(alarm = alarm, onChange = { alarm = it })
    }
}

@Composable
fun RoutineFormDialog(
    initial: RoutineResponse?,
    calendars: List<CalendarResponse>,
    initialCalendarId: Int?,
    persons: List<PersonResponse> = emptyList(),
    onDismiss: () -> Unit,
    onConfirm: (CreateRoutineRequest) -> Unit,
    onDelete: (() -> Unit)? = null
) {
    val context = LocalContext.current
    val isEdit = initial != null

    var title by remember { mutableStateOf(initial?.title.orEmpty()) }
    var calendarId by remember { mutableStateOf(initial?.calendar_id ?: initialCalendarId ?: calendars.firstOrNull()?.id ?: 0) }
    var days by remember { mutableStateOf(initial?.days ?: emptyList()) }
    var time by remember { mutableStateOf(initial?.time?.let { runCatching { LocalTime.parse(it) }.getOrNull() } ?: LocalTime.of(18, 0)) }
    var startDate by remember { mutableStateOf(initial?.start_date?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: LocalDate.now()) }
    var endDate by remember { mutableStateOf(initial?.end_date?.let { runCatching { LocalDate.parse(it) }.getOrNull() }) }
    var active by remember { mutableStateOf(initial?.active ?: true) }
    var alarm by remember { mutableStateOf(initial?.alarm) }
    var personIds by remember { mutableStateOf(initial?.persons.orEmpty().map { it.id }) }

    PlanifyFormSheet(
        title = stringResource(if (isEdit) R.string.routine_edit else R.string.routine_new),
        onDismiss = onDismiss,
        confirmText = stringResource(if (isEdit) R.string.generic_save else R.string.generic_create),
        confirmEnabled = title.isNotBlank() && days.isNotEmpty() && calendars.any { it.id == calendarId },
        onConfirm = {
            onConfirm(CreateRoutineRequest(calendarId, title.trim(), days.sorted(), time.format(timeFormat), startDate.toString(), endDate?.toString(), active, alarm, personIds))
        },
        onDelete = onDelete.takeIf { isEdit }
    ) {
        if (!isEdit) {
            CalendarSelectField(calendars, calendarId) { calendarId = it }
        }
        CustomTextField(
            value = title,
            onValueChange = { title = it },
            label = stringResource(R.string.label_title),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
        )
        FormLabel(stringResource(R.string.routine_days))
        WeekdaySelector(days = days, onChange = { days = it })
        FormPickerField(
            label = stringResource(R.string.label_time),
            value = time.format(timeFormat),
            icon = Icons.Outlined.Schedule,
            onClick = { showTimePicker(context, time) { time = it } }
        )
        FormPickerField(
            label = stringResource(R.string.routine_start),
            value = formatDate(startDate),
            icon = Icons.Outlined.PlayCircle,
            onClick = {
                showDatePicker(context, startDate) { picked ->
                    startDate = picked
                    endDate = endDate?.let { maxOf(it, picked) }
                }
            }
        )
        Box {
            FormPickerField(
                label = stringResource(R.string.routine_end),
                value = endDate?.let { formatDate(it) } ?: stringResource(R.string.routine_no_end),
                icon = Icons.Outlined.EventBusy,
                onClick = { showDatePicker(context, endDate ?: startDate) { endDate = maxOf(it, startDate) } }
            )
            if (endDate != null) {
                IconButton(
                    onClick = { endDate = null },
                    modifier = Modifier.align(Alignment.CenterEnd).padding(top = 8.dp)
                ) {
                    Icon(Icons.Default.Close, contentDescription = stringResource(R.string.routine_no_end), tint = OnSurfaceVariantColor, modifier = Modifier.size(18.dp))
                }
            }
        }
        if (persons.isNotEmpty()) PersonSelector(persons, personIds, onChange = { personIds = it })
        AlarmSelectField(alarm = alarm, onChange = { alarm = it })
        if (isEdit) {
            FormSwitchRow(label = stringResource(R.string.routine_active), checked = active, onCheckedChange = { active = it })
        }
    }
}

@Composable
fun PersonFormDialog(
    initial: PersonResponse?,
    onDismiss: () -> Unit,
    onConfirm: (String, String) -> Unit,
    onDelete: (() -> Unit)? = null
) {
    var name by remember { mutableStateOf(initial?.name.orEmpty()) }
    var color by remember { mutableStateOf(initial?.color ?: randomHueColor()) }

    PlanifyFormSheet(
        title = stringResource(if (initial != null) R.string.person_edit else R.string.person_new),
        onDismiss = onDismiss,
        confirmText = stringResource(if (initial != null) R.string.generic_save else R.string.generic_create),
        confirmEnabled = name.isNotBlank(),
        onConfirm = { onConfirm(name.trim(), color) },
        onDelete = onDelete.takeIf { initial != null }
    ) {
        CustomTextField(
            value = name,
            onValueChange = { name = it.take(50) },
            label = stringResource(R.string.label_name),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words)
        )
        ColorField(color) { color = it }
    }
}

/** Elige qué calendarios y listas se muestran en el dashboard de pared. */
@Composable
fun DashboardFormDialog(
    config: DashboardConfigResponse,
    onDismiss: () -> Unit,
    onConfirm: (List<Int>, List<Int>) -> Unit
) {
    val calendars = remember { config.calendars.filter { it.dashboard }.map { it.id }.toMutableStateList() }
    val taskLists = remember { config.task_lists.filter { it.dashboard }.map { it.id }.toMutableStateList() }

    PlanifyFormSheet(
        title = stringResource(R.string.dashboard_title),
        onDismiss = onDismiss,
        confirmText = stringResource(R.string.generic_save),
        onConfirm = { onConfirm(calendars.toList(), taskLists.toList()) }
    ) {
        listOf(R.string.nav_calendars to (config.calendars to calendars), R.string.tasks_tab_lists to (config.task_lists to taskLists))
            .forEach { (label, group) ->
                val (items, selected) = group
                if (items.isEmpty()) return@forEach
                FormLabel(stringResource(label))
                items.forEach { item ->
                    FormSwitchRow(
                        label = item.name,
                        checked = item.id in selected,
                        onCheckedChange = { if (it) selected.add(item.id) else selected.remove(item.id) },
                        dotColor = parseHexColor(item.color)
                    )
                }
            }
    }
}

@Composable
fun TaskFormDialog(
    initialTitle: String,
    onDismiss: () -> Unit,
    onConfirm: (String, Int?) -> Unit,
    onDelete: (() -> Unit)? = null,
    isEdit: Boolean = true,
    taskLists: List<TaskListResponse> = emptyList()
) {
    var title by remember { mutableStateOf(initialTitle) }
    var listId by remember { mutableStateOf(taskLists.firstOrNull()?.id) }

    PlanifyFormSheet(
        title = stringResource(if (isEdit) R.string.tasks_edit_task else R.string.tasks_new_task),
        onDismiss = onDismiss,
        confirmText = stringResource(if (isEdit) R.string.generic_save else R.string.generic_create),
        confirmEnabled = title.isNotBlank(),
        onConfirm = { onConfirm(title.trim(), listId) },
        onDelete = onDelete.takeIf { isEdit }
    ) {
        if (taskLists.isNotEmpty()) {
            FormSelectField(
                label = stringResource(R.string.label_list),
                selected = listId,
                options = taskLists.map { it.id to it.name },
                onSelect = { listId = it },
                colorOf = { id -> parseHexColor(taskLists.find { it.id == id }?.color) }
            )
        }
        CustomTextField(
            value = title,
            onValueChange = { title = it },
            label = stringResource(R.string.label_title),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
        )
    }
}

@Composable
private fun CalendarSelectField(calendars: List<CalendarResponse>, selectedId: Int, onSelect: (Int) -> Unit) {
    FormSelectField(
        label = stringResource(R.string.label_calendar),
        selected = selectedId,
        options = calendars.map { it.id to it.name },
        onSelect = onSelect,
        colorOf = { id -> parseHexColor(calendars.find { it.id == id }?.color) }
    )
}

@Composable
private fun SettingsTabs(selectedTab: Int, onSelect: (Int) -> Unit) {
    GlassTabs(
        titles = listOf(stringResource(R.string.label_general), stringResource(R.string.label_users)),
        selectedIndex = selectedTab,
        onSelect = onSelect,
        onSheet = true,
        modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)
    )
}

@Composable
private fun ColorField(color: String, onColorChange: (String) -> Unit) {
    Column {
        FormLabel(stringResource(R.string.label_color))
        Spacer(Modifier.height(6.dp))
        HueColorPicker(currentColorHex = color, onColorChange = onColorChange)
    }
}

private data class SharedUser(val userId: Int, val name: String, val email: String, val role: String)

@Composable
private fun UsersSection(users: List<SharedUser>, onInviteUser: (String) -> Unit, onRemoveUser: (Int) -> Unit) {
    var inviteEmail by remember { mutableStateOf("") }

    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CustomTextField(
            value = inviteEmail,
            label = stringResource(R.string.label_email),
            onValueChange = { inviteEmail = it },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            modifier = Modifier.weight(1f)
        )
        IconButton(
            onClick = {
                if (inviteEmail.isNotBlank()) {
                    onInviteUser(inviteEmail.trim())
                    inviteEmail = ""
                }
            },
            enabled = inviteEmail.isNotBlank(),
            modifier = Modifier.padding(top = 8.dp).size(48.dp).background(if (inviteEmail.isNotBlank()) PrimaryColor else OutlineColor, CircleShape)
        ) {
            Icon(Icons.Default.Add, stringResource(R.string.label_invite_user), tint = Color.White)
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        users.forEach { user ->
            UserListItem(name = user.name, email = user.email, role = user.role, onRemove = { onRemoveUser(user.userId) })
        }
    }
}

@Composable
fun UserListItem(
    name: String,
    email: String,
    role: String,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(PillFillColor, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier.size(36.dp).background(PrimaryColor, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(text = name.firstOrNull()?.uppercase() ?: "?", color = Color.White, fontWeight = FontWeight.Bold)
        }

        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
            Text(text = name, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = OnSurfaceColor)
            Text(text = email, style = MaterialTheme.typography.bodySmall, color = OnSurfaceVariantColor)
        }

        if (role == "owner") {
            Text(
                text = stringResource(R.string.role_owner),
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                color = OnPrimaryContainerColor,
                modifier = Modifier
                    .padding(start = 8.dp)
                    .background(PrimaryContainerColor, CircleShape)
                    .padding(horizontal = 12.dp, vertical = 4.dp)
            )
        } else {
            IconButton(onClick = onRemove) {
                Icon(Icons.Default.Delete, stringResource(R.string.generic_delete), tint = OnSurfaceVariantColor, modifier = Modifier.size(20.dp))
            }
        }
    }
}
