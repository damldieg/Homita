package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshContainer
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp

import androidx.compose.ui.graphics.graphicsLayer
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanifyPullToRefreshBox(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    val state = rememberPullToRefreshState()
    val currentIsRefreshing by rememberUpdatedState(isRefreshing)
    var isUserTriggered by remember { mutableStateOf(false) }
    
    if (state.isRefreshing) {
        LaunchedEffect(true) {
            if (!currentIsRefreshing) {
                isUserTriggered = true
                onRefresh()
            }
            // Wait a little bit so the animation is visible
            delay(500)
            while (currentIsRefreshing) {
                delay(100)
            }
            state.endRefresh()
            isUserTriggered = false
        }
    }
    
    LaunchedEffect(isRefreshing) {
        if (isRefreshing && !state.isRefreshing && !isUserTriggered) {
            state.startRefresh()
        } else if (!isRefreshing && state.isRefreshing && !isUserTriggered) {
            state.endRefresh()
        }
    }

    Box(modifier.nestedScroll(state.nestedScrollConnection)) {
        content()
        PullToRefreshContainer(
            state = state,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .graphicsLayer {
                    alpha = if (state.isRefreshing || state.progress > 0f) 1f else 0f
                },
            containerColor = com.lito.planify.ui.theme.SurfaceColor,
            contentColor = MaterialTheme.colorScheme.primary
        )
    }
}

/**
 * Cabecera transparente sobre el degradado, con padding de sistema.
 */
@Composable
fun PlanifyHeader(
    content: @Composable () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().statusBarsPadding()) {
        content()
    }
}

/**
 * El contenedor estándar para listados sobre el fondo degradado.
 */
@Composable
fun PlanifyContentContainer(
    modifier: Modifier = Modifier,
    topPadding: androidx.compose.ui.unit.Dp = 12.dp,
    content: @Composable BoxScope.() -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(top = topPadding)
    ) {
        content()
    }
}
