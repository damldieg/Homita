package com.lito.planify.ui.screens

import androidx.compose.animation.*
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.lito.planify.ui.components.*
import com.lito.planify.ui.theme.OutlineDimColor
import com.lito.planify.viewmodel.TaskListViewModel
import com.lito.planify.viewmodel.TaskViewModel
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TasksScreen(
    taskListId: Int,
    taskListName: String,
    viewModel: TaskViewModel,
    taskListViewModel: TaskListViewModel,
    isStandalone: Boolean = false,
    onBack: (() -> Unit)? = null,
    onNavigateToTasks: (() -> Unit)? = null,
    onNavigateToCalendars: (() -> Unit)? = null,
    onNavigateToProfile: (() -> Unit)? = null
) {
    val tasks by viewModel.tasks.collectAsState()
    val togglingTasks by viewModel.togglingTasks.collectAsState()
    val taskListsState by taskListViewModel.taskLists.collectAsState()
    val isGlobal = taskListId == 0
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE) }

    var selectedListFilterId by remember { 
        val savedId = prefs.getInt("selected_list_filter", -1)
        mutableStateOf<Int?>(if (savedId != -1) savedId else null)
    }
    var newTaskTitle by remember { mutableStateOf("") }
    var showEditDialog by remember { mutableStateOf(false) }
    var selectedTaskToEdit by remember { mutableStateOf<com.lito.planify.data.api.TaskResponse?>(null) }

    if (isStandalone && onBack != null) {
        androidx.activity.compose.BackHandler(onBack = onBack)
    }

    val currentList = remember(taskListsState, taskListId) { taskListsState.find { it.id == taskListId } }
    val displayName = currentList?.name ?: taskListName

    LaunchedEffect(Unit) {
        taskListViewModel.fetchTaskLists()
    }

    LaunchedEffect(taskListId, selectedListFilterId) {
        val effectiveListId = if (isGlobal) selectedListFilterId else taskListId
        viewModel.fetchTasks(taskListId = effectiveListId, force = false)
    }

    if (isStandalone) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            bottomBar = {
                GlassBottomNavBar(
                    currentRoute = "tasks",
                    onNavigate = { route ->
                        when (route) {
                            "tasks" -> onNavigateToTasks?.invoke()
                            "calendars" -> onNavigateToCalendars?.invoke()
                            "profile" -> onNavigateToProfile?.invoke()
                        }
                    }
                )
            }
        ) { padding ->
            Box(modifier = Modifier.fillMaxSize().padding(padding)) {
                TasksViewContent(
                    displayName = displayName,
                    isStandalone = true,
                    isGlobal = false,
                    selectedListFilterId = null,
                    onSetFilter = {},
                    taskLists = taskListsState,
                    tasks = tasks,
                    isRefreshing = viewModel.isLoading.collectAsState().value,
                    onRefresh = { viewModel.fetchTasks(taskListId = taskListId, force = true) },
                    togglingTasks = togglingTasks,
                    newTaskTitle = newTaskTitle,
                    onTitleChange = { newTaskTitle = it },
                    onAddTask = { viewModel.createTask(taskListId, newTaskTitle); newTaskTitle = "" },
                    onTaskToggle = { id, listId, comp -> viewModel.completeTask(id, listId, comp) },
                    onTaskDelete = { id, listId -> viewModel.deleteTask(id, listId) },
                    onReorderTask = { id, pos, lId -> viewModel.reorderTask(id, pos, lId) },
                    onShowEdit = { showEditDialog = true },
                    activeListId = taskListId,
                    sortOrder = currentList?.sort ?: "updated_at",
                    onTaskLongClick = { selectedTaskToEdit = it }
                )
            }
        }
    } else {
        TasksViewContent(
            displayName = displayName,
            isStandalone = false,
            isGlobal = true,
            selectedListFilterId = selectedListFilterId,
            onSetFilter = { 
                selectedListFilterId = it 
                prefs.edit().putInt("selected_list_filter", it ?: -1).apply()
            },
            taskLists = taskListsState,
            tasks = tasks,
            isRefreshing = viewModel.isLoading.collectAsState().value,
            onRefresh = { viewModel.fetchTasks(taskListId = selectedListFilterId, force = true) },
            togglingTasks = togglingTasks,
            newTaskTitle = newTaskTitle,
            onTitleChange = { newTaskTitle = it },
            onAddTask = { viewModel.createTask(selectedListFilterId, newTaskTitle); newTaskTitle = "" },
            onTaskToggle = { id, listId, comp -> viewModel.completeTask(id, listId, comp) },
            onTaskDelete = { id, listId -> viewModel.deleteTask(id, listId) },
            onReorderTask = { id, pos, lId -> viewModel.reorderTask(id, pos, lId) },
            onShowEdit = {},
            activeListId = selectedListFilterId,
            sortOrder = taskListsState.find { it.id == selectedListFilterId }?.sort ?: "updated_at",
            onTaskLongClick = { selectedTaskToEdit = it }
        )
    }

    val taskListUsers by taskListViewModel.taskListUsers.collectAsState()

    LaunchedEffect(showEditDialog) {
        if (showEditDialog && isStandalone) {
            taskListViewModel.fetchTaskListUsers(taskListId)
        }
    }

    if (showEditDialog && isStandalone && currentList != null) {
        CreateTaskListDialog(
            initialName = currentList.name,
            initialColor = currentList.color,
            initialSortOrder = currentList.sort,
            initialWidget = currentList.widget ?: true,
            users = taskListUsers,
            onInviteUser = { email -> taskListViewModel.addTaskListUser(taskListId, email) },
            onRemoveUser = { userId -> taskListViewModel.removeTaskListUser(taskListId, userId) },
            onDismiss = { showEditDialog = false },
            onConfirm = { name, color, sortOrder, widget ->
                taskListViewModel.updateTaskList(taskListId, name, color, sortOrder, widget) {
                    viewModel.fetchTasks(taskListId = taskListId, force = true)
                }
                showEditDialog = false
            },
            onDelete = {
                taskListViewModel.deleteTaskList(taskListId) {
                    onBack?.invoke()
                }
                showEditDialog = false
            },
            isEdit = true
        )
    }

    selectedTaskToEdit?.let { task ->
        TaskFormDialog(
            initialTitle = task.title,
            onDismiss = { selectedTaskToEdit = null },
            onConfirm = { newTitle ->
                val effectiveListId = if (isGlobal) selectedListFilterId else taskListId
                viewModel.updateTask(task.id, effectiveListId, newTitle)
                selectedTaskToEdit = null
            },
            onDelete = {
                val effectiveListId = if (isGlobal) selectedListFilterId else taskListId
                viewModel.deleteTask(task.id, effectiveListId)
                selectedTaskToEdit = null
            },
            isEdit = true
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun TasksViewContent(
    displayName: String,
    isStandalone: Boolean,
    isGlobal: Boolean,
    selectedListFilterId: Int?,
    onSetFilter: (Int?) -> Unit,
    taskLists: List<com.lito.planify.data.api.TaskListResponse>,
    tasks: List<com.lito.planify.data.api.TaskResponse>,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    togglingTasks: Set<Int>,
    newTaskTitle: String,
    onTitleChange: (String) -> Unit,
    onAddTask: () -> Unit,
    onTaskToggle: (Int, Int?, Boolean) -> Unit,
    onTaskDelete: (Int, Int?) -> Unit,
    onReorderTask: (Int, Int, Int?) -> Unit,
    onShowEdit: () -> Unit,
    activeListId: Int?,
    sortOrder: String = "updated_at",
    onTaskLongClick: ((com.lito.planify.data.api.TaskResponse) -> Unit)? = null
) {
    Column(modifier = Modifier.fillMaxSize()) {
        val colorHex = activeListId?.let { id -> taskLists.find { it.id == id }?.color } ?: "#4B4D99"
        val listColor = try { Color(android.graphics.Color.parseColor(colorHex)) } catch (e: Exception) { Color(0xFF4B4D99) }

        if (isStandalone) {
            PlanifyHeader {
                Row(
                    modifier = Modifier.padding(top = 0.dp, start = 24.dp, end = 20.dp, bottom = 16.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(modifier = Modifier.size(14.dp).background(listColor, CircleShape))
                    Spacer(modifier = Modifier.width(12.dp))
                    
                    Text(
                        text = displayName, 
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Serif, fontSize = 34.sp)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    IconButton(onClick = onShowEdit) { Icon(Icons.Default.Settings, null, tint = MaterialTheme.colorScheme.onSurface) }
                }
                HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
            }
        }

        if (isGlobal) {
            Surface(color = Color.White, modifier = Modifier.fillMaxWidth()) {
                Column {
                    HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
                    LazyRow(
                        modifier = Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 10.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        item {
                            PlanifyFilterChip(
                                label = stringResource(R.string.tasks_filter_all),
                                isSelected = selectedListFilterId == null,
                                onClick = { onSetFilter(null) }
                            )
                        }
                        itemsIndexed(taskLists) { _, list ->
                            PlanifyFilterChip(
                                label = list.name,
                                isSelected = selectedListFilterId == list.id,
                                colorHex = list.color,
                                onClick = { onSetFilter(list.id) }
                            )
                        }
                    }
                    HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
                }
            }
        }

        PlanifyContentContainer(
            modifier = Modifier.animateContentSize(animationSpec = tween(300)),
            topPadding = 0.dp
        ) {
            Column {
                val showAdd = activeListId != null && activeListId > 0
                AnimatedVisibility(
                    visible = showAdd,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut()
                ) {
                    Column(modifier = Modifier.background(Color.White)) {
                        Row(
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp).fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            TextField(
                                value = newTaskTitle,
                                onValueChange = onTitleChange,
                                placeholder = { Text(stringResource(R.string.tasks_add_hint), color = Color(0xFF757575), fontSize = 16.sp) },
                                modifier = Modifier.weight(1f),
                                colors = TextFieldDefaults.colors(
                                    focusedContainerColor = Color.Transparent,
                                    unfocusedContainerColor = Color.Transparent,
                                    focusedIndicatorColor = Color.Transparent,
                                    unfocusedIndicatorColor = Color.Transparent
                                ),
                                textStyle = LocalTextStyle.current.copy(fontSize = 16.sp),
                                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences)
                            )
                            FloatingActionButton(
                                onClick = onAddTask,
                                containerColor = listColor,
                                contentColor = Color.White,
                                shape = CircleShape,
                                modifier = Modifier.size(40.dp),
                                elevation = FloatingActionButtonDefaults.elevation(0.dp)
                            ) { Icon(Icons.Default.Add, null) }
                        }
                        HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
                    }
                }

                val pending = tasks.filter { it.completed_at == null }
                val completed = tasks.filter { it.completed_at != null }
                val lazyListState = rememberLazyListState()
                val isReorderEnabled = activeListId != null && sortOrder == "custom"

                val reorderableLazyColumnState = rememberReorderableLazyListState(lazyListState) { from, to ->
                    // Reordering only allowed within the pending tasks section.
                    // Header is at index 0.
                    if (from.index in 1..pending.size && to.index in 1..pending.size) {
                        val task = pending[from.index - 1]
                        onReorderTask(task.id, to.index - 1, activeListId)
                    }
                }

                PlanifyPullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = onRefresh,
                    modifier = Modifier.fillMaxSize()
                ) {
                    LazyColumn(
                        state = lazyListState,
                        modifier = Modifier.fillMaxSize(), 
                        contentPadding = PaddingValues(bottom = 120.dp)
                    ) {
                    if (pending.isNotEmpty()) {
                        item {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(Color(0xFFF7F5F2))
                                    .padding(horizontal = 20.dp, vertical = 18.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.tasks_section_pending, pending.size),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp,
                                        letterSpacing = 1.2.sp
                                    ),
                                    color = Color(0xFF757575)
                                )
                            }
                        }
                        itemsIndexed(pending, key = { _, task -> task.id }) { _, task ->
                            if (isReorderEnabled) {
                                ReorderableItem(reorderableLazyColumnState, key = task.id) { isDragging ->
                                    val elevation by animateDpAsState(if (isDragging) 8.dp else 0.dp)
                                    Surface(shadowElevation = elevation) {
                                        PlanifyTaskRow(
                                            title = task.title, 
                                            colorHex = task.task_list_color, 
                                            isChecked = false, 
                                            isToggling = togglingTasks.contains(task.id),
                                            onToggle = { onTaskToggle(task.id, activeListId, true) }, 
                                            onDelete = { onTaskDelete(task.id, activeListId) },
                                            showLeftColorBar = isGlobal,
                                            modifier = Modifier.draggableHandle().animateItemPlacement(),
                                            onLongClick = { onTaskLongClick?.invoke(task) },
                                            onClick = {}
                                        )
                                    }
                                }
                            } else {
                                PlanifyTaskRow(
                                    title = task.title, 
                                    colorHex = task.task_list_color, 
                                    isChecked = false, 
                                    isToggling = togglingTasks.contains(task.id),
                                    onToggle = { onTaskToggle(task.id, activeListId, true) }, 
                                    onDelete = { onTaskDelete(task.id, activeListId) },
                                    showLeftColorBar = isGlobal,
                                    modifier = Modifier.animateItemPlacement(),
                                    onLongClick = { onTaskLongClick?.invoke(task) },
                                    onClick = {}
                                )
                            }
                        }
                    }
                    if (completed.isNotEmpty()) {
                        item {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(Color(0xFFF7F5F2))
                                    .padding(horizontal = 20.dp, vertical = 18.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.tasks_section_completed, completed.size),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 12.sp,
                                        letterSpacing = 1.2.sp
                                    ),
                                    color = Color(0xFF757575)
                                )
                            }
                        }
                        itemsIndexed(completed, key = { _, task -> task.id }) { _, task ->
                            PlanifyTaskRow(
                                title = task.title, 
                                colorHex = task.task_list_color, 
                                isChecked = true, 
                                isToggling = togglingTasks.contains(task.id),
                                onToggle = { onTaskToggle(task.id, activeListId, false) }, 
                                onDelete = { onTaskDelete(task.id, activeListId) },
                                showLeftColorBar = isGlobal,
                                modifier = Modifier.animateItemPlacement(),
                                onLongClick = { onTaskLongClick?.invoke(task) },
                                onClick = {}
                            )
                        }
                    }
                }
                }
            }
        }
    }
}
