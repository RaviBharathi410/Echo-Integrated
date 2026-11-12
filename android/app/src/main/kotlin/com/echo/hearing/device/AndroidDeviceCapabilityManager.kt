package com.echo.hearing.device

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

data class NativeDeviceOption(
    val id: Int,
    val label: String,
    val type: Int
)

/**
 * Inspects Android AudioManager devices for screening route capabilities and
 * filtered monitor devices (explicitly blocking built-in speakers/earpiece).
 */
class AndroidDeviceCapabilityManager(context: Context) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun getCurrentScreeningRouteMap(): Map<String, Any> {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        var selectedType = "BUILTIN_SPEAKER"
        var displayName = "Built-in Device Speaker"
        var deviceName = "Internal Phone Speaker"
        var isHeadphone = false

        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> {
                    selectedType = "WIRED_HEADPHONES"
                    displayName = "Wired Headphones (3.5mm)"
                    deviceName = device.productName?.toString()?.ifEmpty { "3.5mm Wired Headphones" }
                        ?: "3.5mm Wired Headphones"
                    isHeadphone = true
                    break
                }
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> {
                    selectedType = "WIRED_HEADSET"
                    displayName = "Wired Headset w/ Mic"
                    deviceName = device.productName?.toString()?.ifEmpty { "Wired Headset w/ Mic" }
                        ?: "Wired Headset w/ Mic"
                    isHeadphone = true
                    break
                }
                AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> {
                    selectedType = "USB_HEADSET"
                    displayName = "USB-C Audio / Headset"
                    deviceName = device.productName?.toString()?.ifEmpty { "USB-C Audio Device" }
                        ?: "USB-C Audio Device"
                    isHeadphone = true
                    break
                }
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                    selectedType = "BLUETOOTH_A2DP"
                    displayName = "Bluetooth Audio (A2DP)"
                    deviceName = device.productName?.toString()?.ifEmpty { "Bluetooth Headphones" }
                        ?: "Bluetooth Headphones"
                    isHeadphone = true
                    break
                }
            }
        }

        val calibration = calibrationForRoute(selectedType)
        return mapOf(
            "routeType" to selectedType,
            "routeDisplayName" to displayName,
            "isHeadphone" to isHeadphone,
            "deviceName" to deviceName,
            "isStereoCapable" to true,
            "sampleRateHz" to 44100,
            "calibrationInfo" to calibration
        )
    }

    fun getMonitorInputDevices(): List<NativeDeviceOption> =
        audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .sortedBy(::label)
            .map { NativeDeviceOption(it.id, label(it), it.type) }

    /**
     * Monitor outputs strictly exclude built-in speaker and earpiece to prevent
     * acoustic feedback loops.
     */
    fun getMonitorOutputDevices(): List<NativeDeviceOption> =
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filterNot { isBlockedMonitorOutputType(it.type) }
            .sortedBy(::label)
            .map { NativeDeviceOption(it.id, label(it), it.type) }

    fun isAllowedMonitorOutputId(outputId: Int): Boolean {
        val dev = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.id == outputId }
            ?: return false
        return !isBlockedMonitorOutputType(dev.type)
    }

    fun hasInputDeviceId(inputId: Int): Boolean =
        audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).any { it.id == inputId }

    private fun isBlockedMonitorOutputType(type: Int): Boolean =
        type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
            type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE)

    private fun calibrationForRoute(routeType: String): Map<String, Any> {
        val model = "${Build.MANUFACTURER} ${Build.MODEL}"
        return when (routeType) {
            "WIRED_HEADPHONES", "WIRED_HEADSET", "USB_HEADSET" -> mapOf(
                "deviceModel" to model,
                "routeType" to routeType,
                "provenance" to "FIXTURE_DEFAULT",
                "isOfficiallySupported" to true,
                "profileVersion" to "FIXTURE-HEADPHONE-v0.1",
                "notes" to "Supported physical route for screening. Output levels are digital dBFS and have not been laboratory calibrated."
            )
            "BLUETOOTH_A2DP" -> mapOf(
                "deviceModel" to model,
                "routeType" to routeType,
                "provenance" to "UNCALIBRATED",
                "isOfficiallySupported" to true,
                "profileVersion" to "BT-A2DP-UNCALIBRATED",
                "notes" to "Bluetooth latency and internal DSP compression may introduce timing and level variations. Uncalibrated."
            )
            "BUILTIN_SPEAKER" -> mapOf(
                "deviceModel" to model,
                "routeType" to routeType,
                "provenance" to "UNCALIBRATED",
                "isOfficiallySupported" to false,
                "profileVersion" to "v0.1-provisional",
                "notes" to "Speaker output cannot provide left/right ear acoustic isolation. Earphones or headphones are strictly required."
            )
            else -> mapOf(
                "deviceModel" to model,
                "routeType" to routeType,
                "provenance" to "UNCALIBRATED",
                "isOfficiallySupported" to false,
                "profileVersion" to "v0.1-provisional",
                "notes" to "Audio route is unsupported for audiometric screening."
            )
        }
    }

    private fun label(d: AudioDeviceInfo): String {
        val name = d.productName?.toString()?.takeIf { it.isNotBlank() } ?: "Audio device"
        return "$name · ${typeName(d.type)}"
    }

    private fun typeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in mic"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth mic (SCO)"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone earpiece"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth audio"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        AudioDeviceInfo.TYPE_LINE_ANALOG -> "Analog line"
        AudioDeviceInfo.TYPE_DOCK -> "Dock"
        else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            (type == AudioDeviceInfo.TYPE_BLE_HEADSET || type == AudioDeviceInfo.TYPE_BLE_SPEAKER)
        ) {
            "Bluetooth LE"
        } else {
            "Audio device"
        }
    }
}

