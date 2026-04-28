package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Mic
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
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
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
                        modifier = Modifier.weight(1f).padding(bottom = 8.dp)
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
                Text(text = stringResource(R.string.calendars_new), style = MaterialTheme.typography.headlineMedium)
            }

            if (selectedTab == 0) {
                Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Column {
                        Text(text = stringResource(R.string.label_name).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 8.dp))
                        CustomTextField(
                            value = name, 
                            onValueChange = { name = it }, 
                            label = "",
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
                        )
                    }
                    Column {
                        Text(text = stringResource(R.string.label_color).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 12.dp))
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
                                uncheckedTrackColor = Color(0xFFC8C5BD),
                                uncheckedBorderColor = Color.Transparent
                            )
                        )
                    }
                }
            } else {
                // User Management Tab
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(text = stringResource(R.string.label_invite_user).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = inviteEmail,
                            onValueChange = { inviteEmail = it },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                unfocusedBorderColor = Color(0xFFC8C5BD),
                                focusedBorderColor = Color(0xFF0B57D0),
                                unfocusedContainerColor = Color.White,
                                focusedContainerColor = Color.White
                            ),
                            singleLine = true
                        )
                        IconButton(
                            onClick = { 
                                if (inviteEmail.isNotBlank()) {
                                    onInviteUser(inviteEmail)
                                    inviteEmail = ""
                                }
                            },
                            modifier = Modifier.size(48.dp).background(Color(0xFF0B57D0), RoundedCornerShape(12.dp))
                        ) {
                            Icon(Icons.Default.Add, null, tint = Color.White)
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

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 16.dp).fillMaxWidth()) {
                if (isEdit && onDelete != null) {
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(48.dp)) {
                        Icon(androidx.compose.material.icons.Icons.Default.Delete, contentDescription = "Eliminar", tint = MaterialTheme.colorScheme.error)
                    }
                }
                OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.weight(1f))
                PrimaryButton(text = if(isEdit) stringResource(R.string.generic_save) else stringResource(R.string.generic_create), onClick = { closeWithAnimation { onConfirm(name, selectedColor, widget) } }, enabled = name.isNotBlank(), modifier = Modifier.weight(1f))
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
            .background(Color(0xFFF0EBE1), RoundedCornerShape(16.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            shape = androidx.compose.foundation.shape.CircleShape,
            color = Color(0xFF2874D4),
            modifier = Modifier.size(40.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(text = name.firstOrNull()?.uppercase() ?: "?", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }
        
        Spacer(modifier = Modifier.width(12.dp))
        
        Column(modifier = Modifier.weight(1f)) {
            Text(text = name, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold), color = Color(0xFF1D1B20))
            Text(text = email, style = MaterialTheme.typography.bodySmall, color = Color(0xFF757575))
        }

        if (role == "owner") {
            Surface(
                shape = androidx.compose.foundation.shape.CircleShape,
                color = Color(0xFFD3E3FD),
                modifier = Modifier.padding(start = 8.dp)
            ) {
                Text(
                    text = stringResource(R.string.role_owner), 
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                    color = Color(0xFF041E49)
                )
            }
        } else {
            IconButton(onClick = onRemove) {
                Icon(Icons.Default.Delete, null, tint = Color(0xFF1D1B20), modifier = Modifier.size(20.dp))
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
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
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
                        modifier = Modifier.weight(1f).padding(bottom = 8.dp)
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
                Text(text = stringResource(R.string.tasks_new_list), style = MaterialTheme.typography.headlineMedium)
            }

            if (selectedTab == 0) {
                Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Column {
                        Text(text = stringResource(R.string.label_name).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
                        CustomTextField(
                            value = name, 
                            onValueChange = { name = it }, 
                            label = "",
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
                        )
                    }
                    Column {
                        Text(text = stringResource(R.string.label_order).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 10.dp))
                        
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
                            OutlinedTextField(
                                value = sortOptions.find { it.first == sortOrder }?.second ?: "",
                                onValueChange = {},
                                readOnly = true,
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                                modifier = Modifier.menuAnchor().fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                colors = OutlinedTextFieldDefaults.colors(
                                    unfocusedBorderColor = Color(0xFFC8C5BD),
                                    focusedBorderColor = Color(0xFF0B57D0),
                                    unfocusedContainerColor = Color.White,
                                    focusedContainerColor = Color.White
                                )
                            )
                            ExposedDropdownMenu(
                                expanded = expanded,
                                onDismissRequest = { expanded = false },
                                modifier = Modifier.background(Color.White)
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
                        Text(text = stringResource(R.string.label_color).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 10.dp))
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
                                uncheckedTrackColor = Color(0xFFC8C5BD),
                                uncheckedBorderColor = Color.Transparent
                            )
                        )
                    }
                }
            } else {
                // User Management Tab
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(text = stringResource(R.string.label_invite_user).uppercase(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = inviteEmail,
                            onValueChange = { inviteEmail = it },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                unfocusedBorderColor = Color(0xFFC8C5BD),
                                focusedBorderColor = Color(0xFF0B57D0),
                                unfocusedContainerColor = Color.White,
                                focusedContainerColor = Color.White
                            ),
                            singleLine = true
                        )
                        IconButton(
                            onClick = { 
                                if (inviteEmail.isNotBlank()) {
                                    onInviteUser(inviteEmail)
                                    inviteEmail = ""
                                }
                            },
                            modifier = Modifier.size(48.dp).background(Color(0xFF0B57D0), RoundedCornerShape(12.dp))
                        ) {
                            Icon(Icons.Default.Add, null, tint = Color.White)
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

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 4.dp).fillMaxWidth()) {
                if (isEdit && onDelete != null) {
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(48.dp)) {
                        Icon(androidx.compose.material.icons.Icons.Default.Delete, contentDescription = "Eliminar", tint = MaterialTheme.colorScheme.error)
                    }
                }
                OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.weight(1f))
                PrimaryButton(text = if(isEdit) stringResource(R.string.generic_save) else stringResource(R.string.generic_create), onClick = { closeWithAnimation { onConfirm(name, selectedColor, sortOrder, widget) } }, enabled = name.isNotBlank(), modifier = Modifier.weight(1f))
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
    isEdit: Boolean = false
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
            modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Header
            Text(
                text = if(isEdit) stringResource(R.string.calendars_edit_event) else stringResource(R.string.calendars_new_event), 
                style = MaterialTheme.typography.headlineMedium.copy(
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Serif,
                    fontSize = 32.sp
                )
            )

            // AI Toggle Box
            if (!isEdit) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(64.dp)
                        .background(
                            color = if (isAiMode) Color(0xFFD3E3FD) else Color(0xFFF0EBE1),
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
                            tint = if (isAiMode) Color(0xFF041E49) else Color(0xFF5A5853),
                            modifier = Modifier.size(20.dp)
                        )
                        Text(
                            text = stringResource(R.string.label_ai_assistant),
                            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                            color = if (isAiMode) Color(0xFF041E49) else Color(0xFF5A5853)
                        )
                    }
                    Switch(
                        checked = isAiMode,
                        onCheckedChange = { isAiMode = it },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = Color(0xFF0B57D0),
                            uncheckedThumbColor = Color.White,
                            uncheckedTrackColor = Color(0xFFC8C5BD),
                            uncheckedBorderColor = Color.Transparent
                        )
                    )
                }
            }

            if (isAiMode && !isEdit) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = stringResource(R.string.label_describe_event).uppercase(), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp), color = Color(0xFF757575))
                    OutlinedTextField(
                        value = text,
                        onValueChange = { text = it },
                        modifier = Modifier.fillMaxWidth().height(160.dp),
                        shape = RoundedCornerShape(16.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = Color(0xFF0B57D0),
                            focusedBorderColor = Color(0xFF0B57D0),
                            unfocusedContainerColor = Color.White,
                            focusedContainerColor = Color.White
                        ),
                        trailingIcon = {
                            Box(modifier = Modifier.padding(top = 100.dp, end = 8.dp)) {
                                FloatingActionButton(
                                    onClick = {},
                                    containerColor = Color(0xFF0B57D0),
                                    contentColor = Color.White,
                                    shape = androidx.compose.foundation.shape.CircleShape,
                                    modifier = Modifier.size(40.dp),
                                    elevation = FloatingActionButtonDefaults.elevation(0.dp)
                                ) {
                                    Icon(androidx.compose.material.icons.Icons.Default.Mic, null)
                                }
                            }
                        }
                    )
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = stringResource(R.string.label_title).uppercase(), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp), color = Color(0xFF757575))
                    OutlinedTextField(
                        value = title,
                        onValueChange = { title = it },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = Color(0xFFC8C5BD),
                            focusedBorderColor = Color(0xFF0B57D0),
                            unfocusedContainerColor = Color.White,
                            focusedContainerColor = Color.White
                        ),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(text = stringResource(R.string.label_date_time).uppercase(), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp), color = Color(0xFF757575))
                    OutlinedTextField(
                        value = dateAt,
                        onValueChange = {},
                        readOnly = true,
                        modifier = Modifier.fillMaxWidth().clickable { openDateTimePicker() },
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = Color(0xFFC8C5BD),
                            focusedBorderColor = Color(0xFF0B57D0),
                            disabledBorderColor = Color(0xFFC8C5BD),
                            disabledTextColor = MaterialTheme.colorScheme.onSurface,
                            unfocusedContainerColor = Color.White,
                            focusedContainerColor = Color.White,
                            disabledContainerColor = Color.White
                        ),
                        enabled = false,
                        leadingIcon = { Icon(androidx.compose.material.icons.Icons.Default.DateRange, null, tint = Color(0xFF757575)) },
                        trailingIcon = { Icon(androidx.compose.material.icons.Icons.Default.ArrowDropDown, null, tint = Color(0xFF757575)) }
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(text = stringResource(R.string.label_alarm).uppercase(), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = 1.sp), color = Color(0xFF757575))
                
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
                    OutlinedTextField(
                        value = alarmOptions.find { it.first == alarm }?.second ?: stringResource(R.string.alarm_no),
                        onValueChange = {},
                        readOnly = true,
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = alarmExpanded) },
                        modifier = Modifier.menuAnchor().fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = Color(0xFFC8C5BD),
                            focusedBorderColor = Color(0xFF0B57D0),
                            unfocusedContainerColor = Color.White,
                            focusedContainerColor = Color.White
                        )
                    )
                    ExposedDropdownMenu(
                        expanded = alarmExpanded,
                        onDismissRequest = { alarmExpanded = false },
                        modifier = Modifier.background(Color.White)
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

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
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
