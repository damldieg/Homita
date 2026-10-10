package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Star
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.R
import com.lito.planify.data.api.CalendarUserResponse
import com.lito.planify.data.api.EventResponse
import com.lito.planify.data.api.TaskListUserResponse
import com.lito.planify.ui.theme.OutlineColor
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import kotlinx.coroutines.launch
import com.lito.planify.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateCalendarDialog(
    initialName: String = "",
    initialColor: String = "#5CB8D6",
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
    var selectedColor by remember { mutableStateOf(initialColor) }
    var widget by remember { mutableStateOf(initialWidget) }
    var selectedTab by remember { mutableStateOf(0) }
    var inviteEmail by remember { mutableStateOf("") }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    
    fun closeWithAnimation(action: () -> Unit) {
        scope.launch { sheetState.hide() }.invokeOnCompletion { if (!sheetState.isVisible) action() }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle(width = 36.dp, height = 4.dp, color = OutlineColor) },
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (isEdit) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TabRow(
                        selectedTabIndex = selectedTab,
                        containerColor = Color.Transparent,
                        contentColor = MaterialTheme.colorScheme.primary,
                        divider = {},
                        indicator = { tabPositions ->
                            TabRowDefaults.SecondaryIndicator(
                                Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                                height = 3.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Tab(
                            selected = selectedTab == 0,
                            onClick = { selectedTab = 0 },
                            text = { Text(stringResource(R.string.label_general), fontWeight = if(selectedTab == 0) FontWeight.Bold else FontWeight.Medium) }
                        )
                        Tab(
                            selected = selectedTab == 1,
                            onClick = { selectedTab = 1 },
                            text = { Text(stringResource(R.string.label_users), fontWeight = if(selectedTab == 1) FontWeight.Bold else FontWeight.Medium) }
                        )
                    }
                }
            } else {
                Text(text = stringResource(R.string.calendars_new), style = MaterialTheme.typography.headlineSmall)
            }

            if (selectedTab == 0) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CustomTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = stringResource(R.string.label_name),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
                    )
                    Column {
                        Text(text = stringResource(R.string.label_color), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
                        HueColorPicker(currentColorHex = selectedColor, onColorChange = { selectedColor = it })
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = stringResource(R.string.label_show_in_widget),
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Switch(
                            checked = widget,
                            onCheckedChange = { widget = it },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = MaterialTheme.colorScheme.primary,
                                uncheckedThumbColor = Color.White,
                                uncheckedTrackColor = OutlineColor,
                                uncheckedBorderColor = Color.Transparent
                            )
                        )
                    }
                }
            } else {
                // User Management Tab
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        CustomTextField(
                            value = inviteEmail,
                            label = stringResource(R.string.label_email),
                            onValueChange = { inviteEmail = it },
                            keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Email),
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        IconButton(
                            onClick = { 
                                if (inviteEmail.isNotBlank()) {
                                    onInviteUser(inviteEmail)
                                    inviteEmail = ""
                                }
                            },
                            modifier = Modifier.size(48.dp).background(PrimaryColor, RoundedCornerShape(12.dp))
                        ) {
                            Icon(Icons.Default.Add, stringResource(R.string.label_invite_user), tint = Color.White)
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        users.forEach { user ->
                            UserListItem(
                                name = user.name,
                                email = user.email,
                                role = user.role,
                                onRemove = { onRemoveUser(user.user_id) }
                            )
                        }
                    }
                }
            }

            if (selectedTab == 0) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp).fillMaxWidth()) {
                    if (isEdit && onDelete != null) {
                        IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(48.dp)) {
                            Icon(androidx.compose.material.icons.Icons.Default.Delete, contentDescription = "Eliminar", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                    OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.weight(1f))
                    PrimaryButton(text = if(isEdit) stringResource(R.string.generic_save) else stringResource(R.string.generic_create), onClick = { closeWithAnimation { onConfirm(name, selectedColor, widget) } }, enabled = name.isNotBlank(), modifier = Modifier.weight(1f))
                }
            } else {
                Row(modifier = Modifier.padding(top = 4.dp).fillMaxWidth()) {
                    OutlinedActionButton(text = stringResource(R.string.generic_close), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_text)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    closeWithAnimation(onDelete!!)
                }) {
                    Text(stringResource(R.string.generic_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.generic_cancel))
                }
            }
        )
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
            .background(SurfaceDimColor, RoundedCornerShape(16.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = androidx.compose.foundation.shape.CircleShape,
            color = PrimaryColor,
            modifier = Modifier.size(40.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(text = name.firstOrNull()?.uppercase() ?: "?", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }
        
        Spacer(modifier = Modifier.width(12.dp))
        
        Column(modifier = Modifier.weight(1f)) {
            Text(text = name, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold), color = OnSurfaceColor)
            Text(text = email, style = MaterialTheme.typography.bodySmall, color = OnSurfaceVariantColor)
        }

        if (role == "owner") {
            Surface(
                shape = androidx.compose.foundation.shape.CircleShape,
                color = PrimaryContainerColor,
                modifier = Modifier.padding(start = 8.dp)
            ) {
                Text(
                    text = stringResource(R.string.role_owner), 
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                    color = OnPrimaryContainerColor
                )
            }
        } else {
            IconButton(onClick = onRemove) {
                Icon(Icons.Default.Delete, null, tint = OnSurfaceColor, modifier = Modifier.size(20.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateTaskListDialog(
    initialName: String = "",
    initialColor: String = "#D65C5C",
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
    var selectedColor by remember { mutableStateOf(initialColor) }
    var sortOrder by remember { mutableStateOf(initialSortOrder) }
    var widget by remember { mutableStateOf(initialWidget) }
    var selectedTab by remember { mutableStateOf(0) }
    var inviteEmail by remember { mutableStateOf("") }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    
    fun closeWithAnimation(action: () -> Unit) {
        scope.launch { sheetState.hide() }.invokeOnCompletion { if (!sheetState.isVisible) action() }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle(width = 36.dp, height = 4.dp, color = OutlineColor) },
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (isEdit) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TabRow(
                        selectedTabIndex = selectedTab,
                        containerColor = Color.Transparent,
                        contentColor = MaterialTheme.colorScheme.primary,
                        divider = {},
                        indicator = { tabPositions ->
                            TabRowDefaults.SecondaryIndicator(
                                Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                                height = 3.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Tab(
                            selected = selectedTab == 0,
                            onClick = { selectedTab = 0 },
                            text = { Text(stringResource(R.string.label_general), fontWeight = if(selectedTab == 0) FontWeight.Bold else FontWeight.Medium) }
                        )
                        Tab(
                            selected = selectedTab == 1,
                            onClick = { selectedTab = 1 },
                            text = { Text(stringResource(R.string.label_users), fontWeight = if(selectedTab == 1) FontWeight.Bold else FontWeight.Medium) }
                        )
                    }
                }
            } else {
                Text(text = stringResource(R.string.tasks_new_list), style = MaterialTheme.typography.headlineSmall)
            }

            if (selectedTab == 0) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CustomTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = stringResource(R.string.label_name),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
                    )
                    Column {
                        
                        val sortOptions = listOf(
                            "updated_at" to stringResource(R.string.sort_activity),
                            "title" to stringResource(R.string.sort_alphabetical),
                            "custom" to stringResource(R.string.sort_custom)
                        )
                        var expanded by remember { mutableStateOf(false) }
                        
                        ExposedDropdownMenuBox(
                            expanded = expanded,
                            onExpandedChange = { expanded = !expanded }
                        ) {
                            CustomTextField(
                                value = sortOptions.find { it.first == sortOrder }?.second ?: "",
                                label = stringResource(R.string.label_order),
                                onValueChange = {},
                                readOnly = true,
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                                modifier = Modifier.menuAnchor().fillMaxWidth()
                            )
                            ExposedDropdownMenu(
                                expanded = expanded,
                                onDismissRequest = { expanded = false }
                            ) {
                                sortOptions.forEach { option ->
                                    DropdownMenuItem(
                                        text = { Text(option.second) },
                                        onClick = {
                                            sortOrder = option.first
                                            expanded = false
                                        }
                                    )
                                }
                            }
                        }
                    }
                    Column {
                        Text(text = stringResource(R.string.label_color), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
                        HueColorPicker(currentColorHex = selectedColor, onColorChange = { selectedColor = it })
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = stringResource(R.string.label_show_in_widget),
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Switch(
                            checked = widget,
                            onCheckedChange = { widget = it },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = MaterialTheme.colorScheme.primary,
                                uncheckedThumbColor = Color.White,
                                uncheckedTrackColor = OutlineColor,
                                uncheckedBorderColor = Color.Transparent
                            )
                        )
                    }
                }
            } else {
                // User Management Tab
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        CustomTextField(
                            value = inviteEmail,
                            label = stringResource(R.string.label_email),
                            onValueChange = { inviteEmail = it },
                            keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Email),
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        IconButton(
                            onClick = { 
                                if (inviteEmail.isNotBlank()) {
                                    onInviteUser(inviteEmail)
                                    inviteEmail = ""
                                }
                            },
                            modifier = Modifier.size(48.dp).background(PrimaryColor, RoundedCornerShape(12.dp))
                        ) {
                            Icon(Icons.Default.Add, stringResource(R.string.label_invite_user), tint = Color.White)
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        users.forEach { user ->
                            UserListItem(
                                name = user.name,
                                email = user.email,
                                role = user.role,
                                onRemove = { onRemoveUser(user.user_id) }
                            )
                        }
                    }
                }
            }

            if (selectedTab == 0) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp).fillMaxWidth()) {
                    if (isEdit && onDelete != null) {
                        IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(48.dp)) {
                            Icon(androidx.compose.material.icons.Icons.Default.Delete, contentDescription = "Eliminar", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                    OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.weight(1f))
                    PrimaryButton(text = if(isEdit) stringResource(R.string.generic_save) else stringResource(R.string.generic_create), onClick = { closeWithAnimation { onConfirm(name, selectedColor, sortOrder, widget) } }, enabled = name.isNotBlank(), modifier = Modifier.weight(1f))
                }
            } else {
                Row(modifier = Modifier.padding(top = 4.dp).fillMaxWidth()) {
                    OutlinedActionButton(text = stringResource(R.string.generic_close), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_text)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    closeWithAnimation(onDelete!!)
                }) {
                    Text(stringResource(R.string.generic_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.generic_cancel))
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventFormDialog(
    calendarId: Int,
    initialEvent: EventResponse? = null,
    onDismiss: () -> Unit,
    onConfirm: (Int, String, String, String, Int?) -> Unit,
    onDelete: (() -> Unit)? = null,
    isEdit: Boolean = false,
    onOpenRoutine: (() -> Unit)? = null
) {
    val defaultDate = remember {
        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:00", java.util.Locale.getDefault())
        sdf.format(java.util.Date())
    }
    
    var title by remember { mutableStateOf(initialEvent?.title ?: "") }
    var text by remember { mutableStateOf("") }
    var dateAt by remember { mutableStateOf(initialEvent?.date_at ?: defaultDate) }
    var alarm by remember { mutableStateOf(initialEvent?.alarm) }
    var isAiMode by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    val context = androidx.compose.ui.platform.LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    
    fun closeWithAnimation(action: () -> Unit) {
        scope.launch { sheetState.hide() }.invokeOnCompletion { if (!sheetState.isVisible) action() }
    }
    
    fun openDateTimePicker() {
        val calendar = java.util.Calendar.getInstance()
        try {
            val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            calendar.time = sdf.parse(dateAt) ?: java.util.Date()
        } catch (e: Exception) {}

        android.app.DatePickerDialog(
            context,
            { _, year, month, dayOfMonth ->
                android.app.TimePickerDialog(
                    context,
                    { _, hourOfDay, minute ->
                        calendar.set(year, month, dayOfMonth, hourOfDay, minute, 0)
                        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
                        dateAt = sdf.format(calendar.time)
                    },
                    calendar.get(java.util.Calendar.HOUR_OF_DAY),
                    calendar.get(java.util.Calendar.MINUTE),
                    true
                ).show()
            },
            calendar.get(java.util.Calendar.YEAR),
            calendar.get(java.util.Calendar.MONTH),
            calendar.get(java.util.Calendar.DAY_OF_MONTH)
        ).show()
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle(width = 36.dp, height = 4.dp, color = OutlineColor) },
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Header
            Text(
                text = if(isEdit) stringResource(R.string.calendars_edit_event) else stringResource(R.string.calendars_new_event), 
                style = MaterialTheme.typography.headlineSmall
            )

            if (initialEvent?.routine_id != null) {
                Text(stringResource(R.string.routine_session_only), style = MaterialTheme.typography.bodySmall)
                onOpenRoutine?.let { open ->
                    TextButton(onClick = { closeWithAnimation(open) }) { Text(stringResource(R.string.routine_open)) }
                }
            }

            // AI Toggle Box
            if (!isEdit) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .background(
                            color = if (isAiMode) PrimaryContainerColor else SurfaceDimColor,
                            shape = RoundedCornerShape(12.dp)
                        )
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(
                            androidx.compose.material.icons.Icons.Default.Star, 
                            contentDescription = null,
                            tint = if (isAiMode) OnPrimaryContainerColor else OnSurfaceVariantColor,
                            modifier = Modifier.size(20.dp)
                        )
                        Text(
                            text = stringResource(R.string.label_ai_assistant),
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                            color = if (isAiMode) OnPrimaryContainerColor else OnSurfaceVariantColor
                        )
                    }
                    Switch(
                        checked = isAiMode,
                        onCheckedChange = { isAiMode = it },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = PrimaryColor,
                            uncheckedThumbColor = Color.White,
                            uncheckedTrackColor = OutlineColor,
                            uncheckedBorderColor = Color.Transparent
                        )
                    )
                }
            }

            if (isAiMode && !isEdit) {
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
                CustomTextField(
                    value = dateAt,
                    onValueChange = {},
                    label = stringResource(R.string.label_date_time),
                    readOnly = true,
                    enabled = false,
                    modifier = Modifier.clickable { openDateTimePicker() },
                    leadingIcon = { Icon(Icons.Default.DateRange, null, tint = OnSurfaceVariantColor) },
                    trailingIcon = { Icon(Icons.Default.ArrowDropDown, null, tint = OnSurfaceVariantColor) }
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                
                val alarmOptions = listOf(
                    null to stringResource(R.string.alarm_no),
                    0 to stringResource(R.string.alarm_0),
                    10 to stringResource(R.string.alarm_10),
                    20 to stringResource(R.string.alarm_20),
                    30 to stringResource(R.string.alarm_30),
                    40 to stringResource(R.string.alarm_40),
                    60 to stringResource(R.string.alarm_60)
                )
                var alarmExpanded by remember { mutableStateOf(false) }
                
                ExposedDropdownMenuBox(
                    expanded = alarmExpanded,
                    onExpandedChange = { alarmExpanded = !alarmExpanded }
                ) {
                    CustomTextField(
                        label = stringResource(R.string.label_alarm),
                        value = alarmOptions.find { it.first == alarm }?.second ?: stringResource(R.string.alarm_no),
                        onValueChange = {},
                        readOnly = true,
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = alarmExpanded) },
                        modifier = Modifier.menuAnchor().fillMaxWidth()
                    )
                    ExposedDropdownMenu(
                        expanded = alarmExpanded,
                        onDismissRequest = { alarmExpanded = false }
                    ) {
                        alarmOptions.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.second) },
                                onClick = {
                                    alarm = option.first
                                    alarmExpanded = false
                                }
                            )
                        }
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                if (isEdit && onDelete != null) {
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(48.dp)) {
                        Icon(androidx.compose.material.icons.Icons.Default.Delete, contentDescription = "Eliminar", tint = MaterialTheme.colorScheme.error)
                    }
                }
                OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.weight(1f))
                PrimaryButton(text = if(isEdit) stringResource(R.string.generic_save) else stringResource(R.string.generic_create), onClick = { closeWithAnimation { onConfirm(calendarId, title, dateAt, text, alarm) } }, enabled = isAiMode || title.isNotBlank(), modifier = Modifier.weight(1f))
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_text)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    closeWithAnimation(onDelete!!)
                }) {
                    Text(stringResource(R.string.generic_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.generic_cancel))
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskFormDialog(
    initialTitle: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
    onDelete: (() -> Unit)? = null,
    isEdit: Boolean = true
) {
    var title by remember { mutableStateOf(initialTitle) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    fun closeWithAnimation(action: () -> Unit) {
        scope.launch { sheetState.hide() }.invokeOnCompletion { if (!sheetState.isVisible) action() }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle(width = 36.dp, height = 4.dp, color = OutlineColor) },
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = if (isEdit) stringResource(R.string.tasks_edit_task) else stringResource(R.string.generic_create),
                style = MaterialTheme.typography.headlineSmall
            )

            CustomTextField(
                value = title,
                onValueChange = { title = it },
                label = stringResource(R.string.label_name),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                if (isEdit && onDelete != null) {
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(48.dp)) {
                        Icon(androidx.compose.material.icons.Icons.Default.Delete, contentDescription = "Eliminar", tint = MaterialTheme.colorScheme.error)
                    }
                }
                OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.weight(1f))
                PrimaryButton(
                    text = if(isEdit) stringResource(R.string.generic_save) else stringResource(R.string.generic_create),
                    onClick = { closeWithAnimation { onConfirm(title) } },
                    enabled = title.isNotBlank(),
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_text)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    closeWithAnimation(onDelete!!)
                }) {
                    Text(stringResource(R.string.generic_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.generic_cancel))
                }
            }
        )
    }
}

