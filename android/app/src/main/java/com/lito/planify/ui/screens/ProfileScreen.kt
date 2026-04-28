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
import com.lito.planify.ui.components.OutlinedActionButton
import com.lito.planify.ui.components.PrimaryButton
import com.lito.planify.ui.components.TonalButton
import com.lito.planify.util.TokenManager
import com.lito.planify.viewmodel.AuthViewModel
import java.io.File

@Composable
fun ProfileScreen(
    viewModel: AuthViewModel,
    sessionManager: SessionManager,
    onLogout: () -> Unit,
    onNavigateToTasks: () -> Unit,
    onNavigateToCalendars: () -> Unit
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
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            GlassBottomNavBar(
                currentRoute = "profile",
                onNavigate = { route ->
                    when (route) {
                        "tasks" -> onNavigateToTasks()
                        "calendars" -> onNavigateToCalendars()
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text(
                text = stringResource(R.string.profile_title),
                style = MaterialTheme.typography.displayMedium.copy(
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Serif,
                    fontSize = 44.sp,
                    lineHeight = 44.sp,
                    fontWeight = FontWeight.Normal,
                    letterSpacing = (-1).sp
                ),
                color = Color(0xFF1D1B20),
                modifier = Modifier.padding(bottom = 8.dp)
            )

            // Name Field
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Nombre") },
                leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = Color(0xFF5A5853)) },
                modifier = Modifier.fillMaxWidth(),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Color(0xFFC8C5BD),
                    focusedBorderColor = Color(0xFF0B57D0),
                    unfocusedContainerColor = Color.White,
                    focusedContainerColor = Color.White
                ),
                singleLine = true
            )

            // Email Field
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email") },
                leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = Color(0xFF5A5853)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Color(0xFF0B57D0),
                    focusedBorderColor = Color(0xFF0B57D0),
                    unfocusedContainerColor = Color.White,
                    focusedContainerColor = Color.White
                ),
                singleLine = true
            )

            // Password Field
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Contraseña") },
                leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null, tint = Color(0xFF5A5853)) },
                trailingIcon = {
                    val image = if (passwordVisible) Icons.Default.Visibility else Icons.Default.VisibilityOff
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(imageVector = image, contentDescription = null, tint = Color(0xFF5A5853))
                    }
                },
                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    unfocusedBorderColor = Color(0xFFC8C5BD),
                    focusedBorderColor = Color(0xFF0B57D0),
                    unfocusedContainerColor = Color.White,
                    focusedContainerColor = Color.White
                ),
                singleLine = true
            )

            // Save Button
            Button(
                onClick = { 
                    viewModel.updateProfile(name, email, if (password.isEmpty()) null else password) { }
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(26.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0B57D0))
            ) {
                if (isLoading) {
                    CircularProgressIndicator(color = Color.White, modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                } else {
                    Text(stringResource(R.string.profile_save), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }

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
                            color = Color(0xFF1D1B20)
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = logDate,
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFF757575)
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    
                    // Share Button
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .background(Color.White, androidx.compose.foundation.shape.CircleShape)
                            .border(1.dp, Color(0xFFC8C5BD), androidx.compose.foundation.shape.CircleShape)
                            .clickable { downloadErrorLog(context) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(androidx.compose.ui.res.painterResource(R.drawable.ic_download), null, modifier = Modifier.size(18.dp), tint = Color(0xFF1D1B20))
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
                modifier = Modifier.fillMaxWidth().height(56.dp),
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

@Composable
fun ProfileInputField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge.copy(
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.sp
            ),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        CustomTextField(
            value = value,
            onValueChange = onValueChange,
            label = "", // Keep internal label empty as requested
            leadingIcon = leadingIcon,
            trailingIcon = trailingIcon,
            visualTransformation = visualTransformation,
            keyboardOptions = keyboardOptions
        )
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
