package com.lito.planify.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import com.lito.planify.R
import com.lito.planify.ui.components.GlassNavScaffold
import com.lito.planify.ui.components.GlassTabs
import com.lito.planify.viewmodel.TaskListViewModel
import com.lito.planify.viewmodel.TaskViewModel

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun TasksRootScreen(
    taskListViewModel: TaskListViewModel,
    taskViewModel: TaskViewModel,
    onNavigateToCalendars: () -> Unit,
    onNavigateToProfile: () -> Unit,
    onNavigateToTaskListDetail: (Int, String) -> Unit,
    initialTab: Int = 0
) {
    val pagerState = rememberPagerState(initialPage = initialTab, pageCount = { 2 })
    val coroutineScope = rememberCoroutineScope()
    val selectedTab = pagerState.currentPage
    
    BackHandler(enabled = selectedTab != 0) {
        coroutineScope.launch {
            pagerState.animateScrollToPage(0)
        }
    }
    
    GlassNavScaffold(
        currentRoute = "tasks",
        onNavigate = { route ->
            when (route) {
                "tasks" -> coroutineScope.launch { pagerState.animateScrollToPage(0) }
                "calendars" -> onNavigateToCalendars()
                "profile" -> onNavigateToProfile()
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
        ) {
            GlassTabs(
                titles = listOf(stringResource(R.string.tasks_tab_all), stringResource(R.string.tasks_tab_lists)),
                selectedIndex = selectedTab,
                onSelect = { coroutineScope.launch { pagerState.animateScrollToPage(it) } },
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .fillMaxWidth()
            )

            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f).fillMaxWidth()
            ) { page ->
                when (page) {
                    0 -> TasksScreen(taskListId = 0, taskListName = "Global", viewModel = taskViewModel, taskListViewModel = taskListViewModel)
                    1 -> TaskListsScreen(taskListViewModel, onNavigateToTaskListDetail)
                }
            }
        }
    }
}
