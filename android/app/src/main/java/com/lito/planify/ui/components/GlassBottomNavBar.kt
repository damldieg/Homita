package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Repeat
import com.lito.planify.ui.theme.OnSurfaceColor
import com.lito.planify.ui.theme.OnSurfaceVariantColor

@Composable
fun GlassBottomNavBar(
    currentRoute: String,
    onNavigate: (String) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 16.dp)
    ) {
        // Floating glass pill container
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(64.dp)
                .shadow(
                    elevation = 18.dp,
                    shape = CircleShape,
                    spotColor = Color(0x3314120F)
                )
                .glass(CircleShape, strong = true)
                .padding(6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            val items = listOf(
                Triple("calendars", Icons.Default.DateRange, "Calendarios"),
                Triple("routines", Icons.Default.Repeat, androidx.compose.ui.res.stringResource(com.lito.planify.R.string.routines_title)),
                Triple("tasks", Icons.Default.CheckCircle, "Tareas"),
                Triple("profile", Icons.Default.Person, "Perfil")
            )

            items.forEach { (route, icon, label) ->
                val isSelected = currentRoute.startsWith(route)
                
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .padding(horizontal = 6.dp)
                        .clip(CircleShape)
                        .background(if (isSelected) OnSurfaceColor else Color.Transparent)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null
                        ) { onNavigate(route) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = label,
                        tint = if (isSelected) Color.White else OnSurfaceVariantColor,
                        modifier = Modifier.size(26.dp)
                    )
                }
            }
        }
    }
}

/**
 * Contenedor de pantalla con la barra de cristal superpuesta: el contenido ocupa toda la altura
 * y se desliza por debajo de la barra (el Scaffold de Material 3 lo recortaría encima).
 */
@Composable
fun GlassNavScaffold(
    currentRoute: String,
    onNavigate: (String) -> Unit,
    content: @Composable BoxScope.() -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        content()
        Box(modifier = Modifier.align(Alignment.BottomCenter)) {
            GlassBottomNavBar(currentRoute = currentRoute, onNavigate = onNavigate)
        }
    }
}
