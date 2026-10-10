package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanifyPullToRefreshBox(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    val state = rememberPullToRefreshState()
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        modifier = modifier,
        state = state,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = state,
                isRefreshing = isRefreshing,
                modifier = Modifier.align(Alignment.TopCenter),
                containerColor = com.lito.planify.ui.theme.SurfaceColor,
                color = MaterialTheme.colorScheme.primary
            )
        },
        content = content
    )
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
