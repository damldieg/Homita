package com.lito.planify.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lito.planify.R
import com.lito.planify.ui.components.*
import com.lito.planify.viewmodel.TaskListViewModel

@Composable
fun TaskListsScreen(
    viewModel: TaskListViewModel,
    onNavigateToTaskList: (Int, String) -> Unit
) {
    val taskLists by viewModel.taskLists.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    var showCreateDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.fetchTaskLists() }

    PlanifyContentContainer {
        PlanifyPullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { viewModel.fetchTaskLists(force = true) },
            modifier = Modifier.fillMaxSize()
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 120.dp)
            ) {
                itemsIndexed(taskLists) { _, taskList ->
                    PlanifyRowItem(
                        title = taskList.name,
                        count = taskList.pending_task_count ?: 0,
                        colorHex = taskList.color,
                        onClick = { onNavigateToTaskList(taskList.id, taskList.name) }
                    )
                }
                item {
                    PlanifyDashedCard(
                        text = stringResource(R.string.tasks_new_list),
                        onClick = { showCreateDialog = true }
                    )
                }
            }
        }
    }

    if (showCreateDialog) {
        CreateTaskListDialog(
            onDismiss = { showCreateDialog = false },
            onConfirm = { name, color, sortOrder, widget ->
                viewModel.createTaskList(name, color, sortOrder, widget) { id, listName ->
                    showCreateDialog = false
                    onNavigateToTaskList(id, listName)
                }
            }
        )
    }
}
