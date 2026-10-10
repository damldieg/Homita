package com.lito.planify.ui.screens

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.lito.planify.R
import com.lito.planify.data.local.SessionManager
import com.lito.planify.ui.components.CustomTextField
import com.lito.planify.ui.components.GlassBottomNavBar
import com.lito.planify.ui.components.glass
import com.lito.planify.ui.components.OutlinedActionButton
import com.lito.planify.ui.components.PrimaryButton
import com.lito.planify.ui.components.TonalButton
import com.lito.planify.util.TokenManager
import com.lito.planify.viewmodel.AuthViewModel
import java.io.File
import com.lito.planify.ui.theme.*

@Composable
fun ProfileScreen(
    viewModel: AuthViewModel,
    sessionManager: SessionManager,
    onLogout: () -> Unit,
    onNavigateToTasks: () -> Unit,
    onNavigateToCalendars: () -> Unit,
    onNavigateToRoutines: () -> Unit
) {
    val userName by sessionManager.userNameFlow.collectAsState(initial = "")
    val userEmail by sessionManager.userEmailFlow.collectAsState(initial = "")
    val isLoading by viewModel.isLoading.collectAsState()
    val context = LocalContext.current
    
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }

    LaunchedEffect(userName, userEmail) {
        name = userName ?: ""
        email = userEmail ?: ""
    }

    Scaffold(
        containerColor = Color.Transparent,
        bottomBar = {
            GlassBottomNavBar(
                currentRoute = "profile",
                onNavigate = { route ->
                    when (route) {
                        "tasks" -> onNavigateToTasks()
                        "calendars" -> onNavigateToCalendars()
                        "routines" -> onNavigateToRoutines()
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = stringResource(R.string.profile_title),
                style = MaterialTheme.typography.displayMedium.copy(
                    fontSize = 44.sp,
                    lineHeight = 44.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-1).sp
                ),
                color = OnSurfaceColor,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .glass(androidx.compose.foundation.shape.RoundedCornerShape(28.dp))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Name Field
                CustomTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = stringResource(R.string.label_name),
                    leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = OnSurfaceVariantColor) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                // Email Field
                CustomTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = stringResource(R.string.label_email),
                    leadingIcon = { Icon(Icons.Default.Email, contentDescription = null, tint = OnSurfaceVariantColor) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                // Password Field
                CustomTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = stringResource(R.string.label_password),
                    leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null, tint = OnSurfaceVariantColor) },
                    trailingIcon = {
                        val image = if (passwordVisible) Icons.Default.Visibility else Icons.Default.VisibilityOff
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(imageVector = image, contentDescription = null, tint = OnSurfaceVariantColor)
                        }
                    },
                    visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }

            PrimaryButton(
                text = stringResource(R.string.profile_save),
                onClick = { viewModel.updateProfile(name, email, if (password.isEmpty()) null else password) { } },
                modifier = Modifier.fillMaxWidth(),
                isLoading = isLoading
            )

            Spacer(modifier = Modifier.height(8.dp))

            var hasLogs by remember { mutableStateOf(com.lito.planify.util.CrashReporter.hasCrashDump(context)) }
            val logDate = if (hasLogs) com.lito.planify.util.CrashReporter.getCrashDumpDate(context) else ""

            if (hasLogs) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFFFEF2F2), androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                        .border(1.dp, Color(0xFFFDE6E8), androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier.size(6.dp).background(Color(0xFFDC2626), androidx.compose.foundation.shape.CircleShape)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(verticalArrangement = Arrangement.Center) {
                        Text(
                            text = stringResource(R.string.profile_logs_title),
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                            color = OnSurfaceColor
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = logDate,
                            style = MaterialTheme.typography.bodySmall,
                            color = OnSurfaceVariantColor
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    
                    // Share Button
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .background(Color.White, androidx.compose.foundation.shape.CircleShape)
                            .border(1.dp, OutlineColor, androidx.compose.foundation.shape.CircleShape)
                            .clickable { downloadErrorLog(context) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(androidx.compose.ui.res.painterResource(R.drawable.ic_download), null, modifier = Modifier.size(18.dp), tint = OnSurfaceColor)
                    }
                    
                    Spacer(modifier = Modifier.width(8.dp))

                    // Delete Button
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .background(Color.White, androidx.compose.foundation.shape.CircleShape)
                            .border(1.dp, Color(0xFFFDE6E8), androidx.compose.foundation.shape.CircleShape)
                            .clickable { 
                                clearErrorLog(context)
                                hasLogs = false
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Delete, null, modifier = Modifier.size(16.dp), tint = Color(0xFFDC2626))
                    }
                }
            }

            OutlinedButton(
                onClick = {
                    TokenManager(context).clearToken()
                    viewModel.logout { onLogout() }
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFFFDE6E8)),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFDC2626))
            ) {
                Row(
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.AutoMirrored.Filled.ExitToApp, null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(stringResource(R.string.profile_logout), fontSize = 16.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

private fun downloadErrorLog(context: Context) {
    try {
        val logFile = File(context.filesDir, "crash_dump.txt")
        if (!logFile.exists()) {
            logFile.writeText(context.getString(R.string.profile_logs_empty))
        }
        
        val authority = "${context.packageName}.fileprovider"
        val uri = FileProvider.getUriForFile(context, authority, logFile)
        
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.profile_download_logs)))
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

private fun clearErrorLog(context: Context) {
    try {
        val logFile = File(context.filesDir, "crash_dump.txt")
        if (logFile.exists()) {
            logFile.delete()
        }
        android.widget.Toast.makeText(context, context.getString(R.string.profile_logs_cleared), android.widget.Toast.LENGTH_SHORT).show()
    } catch (e: Exception) {
        e.printStackTrace()
    }
}
