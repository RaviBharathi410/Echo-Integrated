package com.echo.hearing.data

import android.content.Context

data class UserProfile(
    val onboardingCompleted: Boolean = false,
    val initialScreeningCompleted: Boolean = false,
    val accountMode: String = "Guest",
    val email: String = "",
    val preferredName: String = "Alex Parker",
    val ageRange: String = "18–35",
    val preferredLanguage: String = "English",
    val notificationsEnabled: Boolean = true,
    val bluetoothEnabled: Boolean = true,
    val reminderFrequency: String = "Monthly",
    val useSixFrequencies: Boolean = false
)

class UserProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences("echo_user_profile", Context.MODE_PRIVATE)

    fun load(): UserProfile = UserProfile(
        onboardingCompleted = prefs.getBoolean(K_ONBOARDED, false),
        initialScreeningCompleted = prefs.getBoolean(K_INITIAL_TEST, false),
        accountMode = prefs.getString(K_ACCOUNT_MODE, "Guest") ?: "Guest",
        email = prefs.getString(K_EMAIL, "") ?: "",
        preferredName = prefs.getString(K_NAME, "Alex Parker") ?: "Alex Parker",
        ageRange = prefs.getString(K_AGE, "18–35") ?: "18–35",
        preferredLanguage = prefs.getString(K_LANG, "English") ?: "English",
        notificationsEnabled = prefs.getBoolean(K_NOTIF, true),
        bluetoothEnabled = prefs.getBoolean(K_BT, true),
        reminderFrequency = prefs.getString(K_REMINDER, "Monthly") ?: "Monthly",
        useSixFrequencies = prefs.getBoolean(K_SIX_FREQ, false)
    )

    fun save(profile: UserProfile) {
        prefs.edit()
            .putBoolean(K_ONBOARDED, profile.onboardingCompleted)
            .putBoolean(K_INITIAL_TEST, profile.initialScreeningCompleted)
            .putString(K_ACCOUNT_MODE, profile.accountMode)
            .putString(K_EMAIL, profile.email)
            .putString(K_NAME, profile.preferredName)
            .putString(K_AGE, profile.ageRange)
            .putString(K_LANG, profile.preferredLanguage)
            .putBoolean(K_NOTIF, profile.notificationsEnabled)
            .putBoolean(K_BT, profile.bluetoothEnabled)
            .putString(K_REMINDER, profile.reminderFrequency)
            .putBoolean(K_SIX_FREQ, profile.useSixFrequencies)
            .apply()
    }

    fun resetOnboarding() {
        prefs.edit().putBoolean(K_ONBOARDED, false).apply()
    }

    fun signOut() {
        prefs.edit()
            .putBoolean(K_ONBOARDED, false)
            .putBoolean(K_INITIAL_TEST, false)
            .apply()
    }

    private companion object {
        const val K_ONBOARDED = "onboarding_completed"
        const val K_INITIAL_TEST = "initial_screening_completed"
        const val K_ACCOUNT_MODE = "account_mode"
        const val K_EMAIL = "account_email"
        const val K_NAME = "preferred_name"
        const val K_AGE = "age_range"
        const val K_LANG = "preferred_language"
        const val K_NOTIF = "notifications_enabled"
        const val K_BT = "bluetooth_enabled"
        const val K_REMINDER = "reminder_frequency"
        const val K_SIX_FREQ = "use_six_frequencies"
    }
}

