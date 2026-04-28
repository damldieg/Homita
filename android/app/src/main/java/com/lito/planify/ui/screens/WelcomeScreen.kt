package com.lito.planify.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.R
import com.lito.planify.ui.components.PlanifyLogo
import com.lito.planify.ui.components.PrimaryButton
import com.lito.planify.ui.components.TonalButton

@Composable
fun WelcomeScreen(
    onNavigateToLogin: () -> Unit,
    onNavigateToRegister: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFEAF4FB))
            .systemBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 32.dp, vertical = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.Center
            ) {
                PlanifyLogo(size = 140.dp)
                
                Spacer(modifier = Modifier.height(24.dp))
                
                Text(
                    text = "Planify",
                    style = MaterialTheme.typography.displayLarge.copy(
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Serif,
                        fontSize = 56.sp,
                        fontWeight = FontWeight.Normal,
                        letterSpacing = (-1).sp
                    ),
                    color = Color(0xFF1D1B20)
                )
            }

            Column(
                modifier = Modifier.fillMaxWidth().padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Button(
                    onClick = onNavigateToLogin,
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFF2874D4),
                        contentColor = Color.White
                    )
                ) {
                    Text(text = stringResource(R.string.welcome_login), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
                
                Button(
                    onClick = onNavigateToRegister,
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFD2E4F9),
                        contentColor = Color(0xFF041E49)
                    ),
                    elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 0.dp)
                ) {
                    Text(text = stringResource(R.string.welcome_register), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}
