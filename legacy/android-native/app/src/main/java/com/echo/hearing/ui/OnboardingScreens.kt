package com.echo.hearing.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.echo.hearing.data.UserProfile
import com.echo.hearing.ui.components.*
import com.echo.hearing.ui.theme.*

enum class OnboardingStep {
    WELCOME,
    ACCOUNT,
    PROFILE_SETUP,
    HEALTH_NOTICE,
    PERMISSIONS
}

@Composable
fun OnboardingFlow(
    profile: UserProfile,
    needsInitialTest: Boolean = !profile.initialScreeningCompleted,
    onUpdateProfile: (UserProfile) -> Unit,
    onConsentAgreed: () -> Unit,
    onRequestMicrophonePermission: () -> Unit,
    onCompleteOnboarding: () -> Unit
) {
    var step by remember { mutableStateOf(OnboardingStep.WELCOME) }
    var skipProfileSetup by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EchoBg)
    ) {
        when (step) {
            OnboardingStep.WELCOME -> WelcomeScreen(
                onGetStarted = {
                    skipProfileSetup = false
                    step = OnboardingStep.PROFILE_SETUP
                },
                onAlreadyHaveAccount = { step = OnboardingStep.ACCOUNT }
            )

            OnboardingStep.ACCOUNT -> AccountScreen(
                initialEmail = profile.email,
                onBack = { step = OnboardingStep.WELCOME },
                onSignInOrRegister = { mode, email ->
                    val derivedName = if (profile.preferredName.isBlank() || profile.preferredName == "Alex Parker") {
                        email.substringBefore("@").replaceFirstChar { it.uppercase() }.ifBlank { "Alex Parker" }
                    } else {
                        profile.preferredName
                    }
                    onUpdateProfile(profile.copy(accountMode = mode, email = email, preferredName = derivedName))
                    if (mode == "Signed In") {
                        skipProfileSetup = true
                        step = OnboardingStep.HEALTH_NOTICE
                    } else {
                        skipProfileSetup = false
                        step = OnboardingStep.PROFILE_SETUP
                    }
                },
                onContinueAsGuest = {
                    onUpdateProfile(profile.copy(accountMode = "Guest"))
                    skipProfileSetup = false
                    step = OnboardingStep.PROFILE_SETUP
                }
            )

            OnboardingStep.PROFILE_SETUP -> ProfileSetupScreen(
                profile = profile,
                onBack = { step = OnboardingStep.WELCOME },
                onContinue = { updated ->
                    onUpdateProfile(updated)
                    step = OnboardingStep.HEALTH_NOTICE
                }
            )

            OnboardingStep.HEALTH_NOTICE -> HealthNoticeScreen(
                onBack = { step = if (skipProfileSetup) OnboardingStep.ACCOUNT else OnboardingStep.PROFILE_SETUP },
                onAccept = {
                    onConsentAgreed()
                    step = OnboardingStep.PERMISSIONS
                }
            )

            OnboardingStep.PERMISSIONS -> PermissionsScreen(
                profile = profile,
                needsInitialTest = needsInitialTest,
                onBack = { step = OnboardingStep.HEALTH_NOTICE },
                onRequestMicPermission = onRequestMicrophonePermission,
                onUpdateProfile = onUpdateProfile,
                onContinue = {
                    onUpdateProfile(profile.copy(onboardingCompleted = true))
                    onCompleteOnboarding()
                }
            )
        }
    }
}

@Composable
private fun WelcomeScreen(
    onGetStarted: () -> Unit,
    onAlreadyHaveAccount: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "ECHO")
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Spacer(modifier = Modifier.height(4.dp))
            EchoIconBadge(
                icon = Icons.Filled.GraphicEq,
                sizeDp = 72,
                iconSizeDp = 34,
                isCircle = true,
                containerColor = EchoPrimarySoft,
                tint = EchoPrimary
            )
            Text(
                text = "Welcome to ECHO",
                color = EchoNavy,
                fontSize = 28.sp,
                fontWeight = FontWeight.ExtraBold,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Personalized hearing clarity and daily listening monitoring.",
                color = EchoTextMuted,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
                lineHeight = 22.sp
            )

            Spacer(modifier = Modifier.height(6.dp))

            WelcomeFeatureCard(
                icon = Icons.Outlined.Hearing,
                title = "Preliminary Sound Screening",
                description = "Fast, non-clinical tone response checks across key speech frequencies."
            )
            WelcomeFeatureCard(
                icon = Icons.Outlined.Headphones,
                title = "Acoustic Monitoring",
                description = "Real-time Oboe DSP live monitor, ambient noise checks, and exposure tracking."
            )
            WelcomeFeatureCard(
                icon = Icons.Outlined.Tune,
                title = "Sound Personalization",
                description = "Customizable multi-band equalization and speech clarity tools tailored to you."
            )

            Spacer(modifier = Modifier.weight(1f))
            Spacer(modifier = Modifier.height(8.dp))

            EchoPrimaryButton(
                text = "Get Started",
                icon = Icons.AutoMirrored.Filled.ArrowForward,
                onClick = onGetStarted
            )
            EchoOutlinedPillButton(
                text = "I Already Have an Account",
                onClick = onAlreadyHaveAccount
            )
        }
    }
}

@Composable
private fun WelcomeFeatureCard(
    icon: ImageVector,
    title: String,
    description: String
) {
    EchoCard {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoIconBadge(icon = icon, sizeDp = 46, iconSizeDp = 24)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    color = EchoNavy,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(3.dp))
                Text(
                    text = description,
                    color = EchoTextMuted,
                    fontSize = 13.sp,
                    lineHeight = 18.sp
                )
            }
        }
    }
}

@Composable
private fun AccountScreen(
    initialEmail: String,
    onBack: () -> Unit,
    onSignInOrRegister: (mode: String, email: String) -> Unit,
    onContinueAsGuest: () -> Unit
) {
    var isSignIn by remember { mutableStateOf(true) }
    var email by remember { mutableStateOf(if (initialEmail.isBlank()) "alex@example.com" else initialEmail) }
    var password by remember { mutableStateOf("password123") }

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Account", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = if (isSignIn) "Welcome Back" else "Create Local Profile",
                    color = EchoNavy,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Sign in to access your saved screening history.",
                    color = EchoTextMuted,
                    fontSize = 14.sp
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Button(
                    onClick = { isSignIn = true },
                    modifier = Modifier.weight(1f).height(46.dp),
                    shape = RoundedCornerShape(50),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (isSignIn) EchoPrimary else EchoSurfaceAlt,
                        contentColor = if (isSignIn) Color.White else EchoPrimary
                    ),
                    border = if (!isSignIn) BorderStroke(1.dp, EchoPillBorder) else null
                ) {
                    Text("Sign In", fontWeight = FontWeight.SemiBold)
                }
                Button(
                    onClick = { isSignIn = false },
                    modifier = Modifier.weight(1f).height(46.dp),
                    shape = RoundedCornerShape(50),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (!isSignIn) EchoPrimary else EchoSurfaceAlt,
                        contentColor = if (!isSignIn) Color.White else EchoPrimary
                    ),
                    border = if (isSignIn) BorderStroke(1.dp, EchoPillBorder) else null
                ) {
                    Text("Register", fontWeight = FontWeight.SemiBold)
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Email Address", color = EchoNavy, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    leadingIcon = { Icon(Icons.Outlined.Email, contentDescription = null, tint = EchoPrimary) },
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = EchoSurface,
                        unfocusedContainerColor = EchoSurface,
                        focusedBorderColor = EchoPrimary,
                        unfocusedBorderColor = EchoBorder
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Password", color = EchoNavy, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    leadingIcon = { Icon(Icons.Outlined.Lock, contentDescription = null, tint = EchoPrimary) },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = EchoSurface,
                        unfocusedContainerColor = EchoSurface,
                        focusedBorderColor = EchoPrimary,
                        unfocusedBorderColor = EchoBorder
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            EchoPrimaryButton(
                text = if (isSignIn) "Sign In" else "Register",
                icon = Icons.Default.Check,
                onClick = { onSignInOrRegister(if (isSignIn) "Signed In" else "Registered", email.trim()) }
            )

            EchoOutlinedPillButton(
                text = "Continue as Guest",
                icon = Icons.Outlined.PersonOutline,
                onClick = onContinueAsGuest
            )

            Text(
                text = "Local authentication simulation for on-device profile storage. No credentials or audio are transmitted externally.",
                color = EchoTextMuted,
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                lineHeight = 18.sp,
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp)
            )
        }
    }
}

@Composable
private fun ProfileSetupScreen(
    profile: UserProfile,
    onBack: () -> Unit,
    onContinue: (UserProfile) -> Unit
) {
    var name by remember(profile.preferredName) { mutableStateOf(profile.preferredName) }
    var ageRange by remember(profile.ageRange) { mutableStateOf(profile.ageRange) }
    var language by remember(profile.preferredLanguage) { mutableStateOf(profile.preferredLanguage) }

    val ageOptions = listOf("18–35", "36–50", "51–65", "65+")
    val langOptions = listOf("English", "Spanish", "French", "German")

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Profile Setup", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "Your Profile",
                    color = EchoNavy,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Configure baseline details to personalize your audio experience.",
                    color = EchoTextMuted,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Preferred Name", color = EchoNavy, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    leadingIcon = { Icon(Icons.Outlined.Badge, contentDescription = null, tint = EchoPrimary) },
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = EchoSurface,
                        unfocusedContainerColor = EchoSurface,
                        focusedBorderColor = EchoPrimary,
                        unfocusedBorderColor = EchoBorder
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Age Range", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Used for non-clinical demographic baseline context.",
                    color = EchoTextMuted,
                    fontSize = 12.sp
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    ageOptions.forEach { option ->
                        val selected = ageRange == option
                        EchoChoiceChip(
                            label = option,
                            selected = selected,
                            leadingIcon = if (selected) Icons.Default.Check else null,
                            onClick = { ageRange = option }
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Preferred Language", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Interface language for audio instructions and screening prompts.",
                    color = EchoTextMuted,
                    fontSize = 12.sp
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    langOptions.forEach { option ->
                        val selected = language == option
                        EchoChoiceChip(
                            label = option,
                            selected = selected,
                            leadingIcon = if (selected) Icons.Default.Check else null,
                            onClick = { language = option }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            EchoPrimaryButton(
                text = "Continue to Disclaimer",
                icon = Icons.AutoMirrored.Filled.ArrowForward,
                onClick = {
                    onContinue(
                        profile.copy(
                            preferredName = name.ifBlank { "Alex Parker" },
                            ageRange = ageRange,
                            preferredLanguage = language
                        )
                    )
                }
            )
        }
    }
}

@Composable
private fun HealthNoticeScreen(
    onBack: () -> Unit,
    onAccept: () -> Unit
) {
    var agreed by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Health Notice", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            EchoCard {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Info,
                        contentDescription = null,
                        tint = EchoPrimary,
                        modifier = Modifier.size(26.dp)
                    )
                    Text(
                        text = "Important Health Notice",
                        color = EchoNavy,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Spacer(modifier = Modifier.height(14.dp))
                Text(
                    text = "ECHO provides a preliminary screening, not a substitute for professional audiological assessment.",
                    color = EchoNavy,
                    fontSize = 15.sp,
                    lineHeight = 22.sp
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "This software application does not perform calibrated medical diagnosis or clinical audiometry. Sound response indicators use digital attenuation (dBFS), not calibrated dB HL. Ambient exposure levels and listening estimates are indicative only.",
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 20.sp
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "If you experience persistent ear discomfort, tinnitus, or sudden changes in hearing ability, consult a certified audiologist or physician.",
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 20.sp
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Checkbox(
                    checked = agreed,
                    onCheckedChange = { agreed = it },
                    colors = CheckboxDefaults.colors(
                        checkedColor = EchoPrimary,
                        uncheckedColor = EchoTextMuted
                    )
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "I understand that ECHO provides a preliminary screening, not a substitute for professional audiological assessment.",
                    color = EchoNavy,
                    fontSize = 13.5.sp,
                    lineHeight = 19.sp
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            EchoPrimaryButton(
                text = "Accept & Continue",
                icon = Icons.Default.Check,
                enabled = agreed,
                onClick = onAccept
            )
        }
    }
}

@Composable
private fun PermissionsScreen(
    profile: UserProfile,
    needsInitialTest: Boolean,
    onBack: () -> Unit,
    onRequestMicPermission: () -> Unit,
    onUpdateProfile: (UserProfile) -> Unit,
    onContinue: () -> Unit
) {
    var micEnabled by remember { mutableStateOf(true) }
    var notifEnabled by remember(profile.notificationsEnabled) { mutableStateOf(profile.notificationsEnabled) }
    var btEnabled by remember(profile.bluetoothEnabled) { mutableStateOf(profile.bluetoothEnabled) }

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Permissions", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "System Permissions",
                    color = EchoNavy,
                    fontSize = 23.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Microphone access enables real-time ambient noise gating and live audio monitoring. Audio is analyzed transiently in RAM only.",
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 20.sp
                )
            }

            PermissionToggleCard(
                icon = Icons.Outlined.Mic,
                title = "Microphone Permission",
                subtitle = "Ambient noise monitoring & live audio DSP capture.",
                checked = micEnabled,
                onCheckedChange = {
                    micEnabled = it
                    if (it) onRequestMicPermission()
                }
            )
            PermissionToggleCard(
                icon = Icons.Outlined.Notifications,
                title = "Notifications Permission",
                subtitle = "Daily listening reminders and summary alerts.",
                checked = notifEnabled,
                onCheckedChange = {
                    notifEnabled = it
                    onUpdateProfile(profile.copy(notificationsEnabled = it))
                }
            )
            PermissionToggleCard(
                icon = Icons.Outlined.Bluetooth,
                title = "Bluetooth Permission",
                subtitle = "Wireless headphone connection and audio route detection.",
                checked = btEnabled,
                onCheckedChange = {
                    btEnabled = it
                    onUpdateProfile(profile.copy(bluetoothEnabled = it))
                }
            )

            if (needsInitialTest) {
                EchoCard(borderColor = EchoPillBorder, containerColor = EchoSurfaceAlt) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.Hearing, contentDescription = null, tint = EchoPrimary)
                        Column {
                            Text("Up Next: Initial Hearing Baseline Test", color = EchoNavy, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            Text(
                                "Once you continue, ECHO runs an initial pure-tone check to capture your baseline hearing input.",
                                color = EchoTextMuted,
                                fontSize = 12.5.sp,
                                lineHeight = 18.sp
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            EchoPrimaryButton(
                text = if (needsInitialTest) "Continue to Initial Hearing Test" else "Continue to Device Setup",
                icon = Icons.AutoMirrored.Filled.ArrowForward,
                onClick = {
                    if (micEnabled) onRequestMicPermission()
                    onContinue()
                }
            )
        }
    }
}

@Composable
private fun PermissionToggleCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    EchoCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            EchoIconBadge(icon = icon, sizeDp = 44, iconSizeDp = 22)
            Column(modifier = Modifier.weight(1f)) {
                Text(title, color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(2.dp))
                Text(subtitle, color = EchoTextMuted, fontSize = 12.5.sp, lineHeight = 17.sp)
            }
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = EchoPrimary,
                    uncheckedThumbColor = Color.White,
                    uncheckedTrackColor = EchoBorder
                )
            )
        }
    }
}

