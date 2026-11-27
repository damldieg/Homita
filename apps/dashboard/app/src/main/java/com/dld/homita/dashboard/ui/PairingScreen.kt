package com.dld.homita.dashboard.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dld.homita.dashboard.R
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.PairingState
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Pantalla sin sesión (dashboard-pantalla-hogar): enseña un código de 6 dígitos para vincularla desde el móvil
 * (Perfil → Hogar → Pantallas). La pantalla sondea sola hasta que el hogar la confirma. Cinco toques en el logo
 * muestran el acceso técnico con email y contraseña (Q4).
 */
@Composable
fun PairingScreen(state: UiState, onWifi: () -> Unit, onLogoTap: () -> Unit) {
    if (!state.connected) {
        WaitingForNetwork(onWifi)
        return
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.width(900.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(28.dp)) {
            Image(
                painterResource(R.drawable.homita_icon),
                contentDescription = "Homita",
                modifier = Modifier
                    .size(144.dp)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onLogoTap)
            )
            Text("Vincula esta pantalla", style = Type.Huge.copy(fontSize = Type.Title.fontSize * 1.6f), textAlign = TextAlign.Center)
            when (val pairing = state.pairing) {
                is PairingState.Waiting -> {
                    Text(
                        pairing.code.chunked(3).joinToString("  "),
                        style = Type.Mono.copy(fontSize = 150.sp, lineHeight = 160.sp, letterSpacing = 6.sp, color = Palette.Ink),
                        textAlign = TextAlign.Center,
                        maxLines = 1
                    )
                    Text(
                        "En Homita, ve a Perfil → Hogar → Pantallas → Vincular pantalla y escribe este código.",
                        style = Type.Body.copy(color = Palette.InkSoft),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text("Caduca a las ${clock(pairing.expiresAtMillis)}", style = Type.Small.copy(color = Palette.InkMuted), textAlign = TextAlign.Center)
                }
                is PairingState.Failed -> Text(
                    "No se pudo pedir el código. Reintentando…",
                    style = Type.Body.copy(color = Palette.InkMuted),
                    textAlign = TextAlign.Center
                )
                else -> Text("Generando código…", style = Type.Body.copy(color = Palette.InkMuted), textAlign = TextAlign.Center)
            }
        }
    }
}

private val HOUR_MINUTE: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

/** Hora local de un instante en epoch ms, «HH:mm». */
private fun clock(millis: Long): String = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).format(HOUR_MINUTE)
