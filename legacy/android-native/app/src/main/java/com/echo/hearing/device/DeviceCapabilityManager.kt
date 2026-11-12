package com.echo.hearing.device

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.echo.hearing.domain.model.AudioRouteInfo
import com.echo.hearing.domain.model.AudioRouteType
import com.echo.hearing.domain.model.CalibrationInfo
import com.echo.hearing.domain.model.CalibrationProvenance

/**
 * Interface managing device audio output routing and calibration provenance.
 */
interface DeviceCapabilityManager {
    fun getCurrentAudioRoute(): AudioRouteInfo
    fun isHeadphoneConnected(): Boolean
    fun getCalibrationStatus(route: AudioRouteType): CalibrationInfo
}

/**
 * Android implementation inspecting AudioManager outputs.
 */
class AndroidDeviceCapabilityManager(
    private val context: Context
) : DeviceCapabilityManager {

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun getCurrentAudioRoute(): AudioRouteInfo {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

        // Find primary output device (prefer wired headphones, USB headset, Bluetooth A2DP)
        var selectedType = AudioRouteType.BUILTIN_SPEAKER
        var deviceName = "Internal Phone Speaker"

        for (device in devices) {
            when (device.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> {
                    selectedType = AudioRouteType.WIRED_HEADPHONES
                    deviceName = device.productName.toString().ifEmpty { "3.5mm Wired Headphones" }
                    break
                }
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> {
                    selectedType = AudioRouteType.WIRED_HEADSET
                    deviceName = device.productName.toString().ifEmpty { "Wired Headset w/ Mic" }
                    break
                }
                AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> {
                    selectedType = AudioRouteType.USB_HEADSET
                    deviceName = device.productName.toString().ifEmpty { "USB-C Audio Device" }
                    break
                }
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                    selectedType = AudioRouteType.BLUETOOTH_A2DP
                    deviceName = device.productName.toString().ifEmpty { "Bluetooth Headphones" }
                    break
                }
            }
        }

        val calibration = getCalibrationStatus(selectedType)

        return AudioRouteInfo(
            routeType = selectedType,
            deviceName = deviceName,
            isStereoCapable = true,
            sampleRateHz = 44100,
            calibrationInfo = calibration
        )
    }

    override fun isHeadphoneConnected(): Boolean {
        val route = getCurrentAudioRoute()
        return route.routeType.isHeadphone
    }

    override fun getCalibrationStatus(route: AudioRouteType): CalibrationInfo {
        val model = "${Build.MANUFACTURER} ${Build.MODEL}"

        // Clinical calibration requires IEC artificial ear characterization for specific phone + headphone.
        // Arbitrary Android devices and generic headphones are UNCALIBRATED.
        return when (route) {
            AudioRouteType.WIRED_HEADPHONES, AudioRouteType.WIRED_HEADSET, AudioRouteType.USB_HEADSET -> {
                CalibrationInfo(
                    deviceModel = model,
                    routeType = route,
                    provenance = CalibrationProvenance.FIXTURE_DEFAULT,
                    isOfficiallySupported = true,
                    profileVersion = "FIXTURE-HEADPHONE-v0.1",
                    notes = "Supported physical route for screening. Output levels are digital dBFS and have not been laboratory calibrated."
                )
            }
            AudioRouteType.BLUETOOTH_A2DP -> {
                CalibrationInfo(
                    deviceModel = model,
                    routeType = route,
                    provenance = CalibrationProvenance.UNCALIBRATED,
                    isOfficiallySupported = true,
                    profileVersion = "BT-A2DP-UNCALIBRATED",
                    notes = "Bluetooth latency and internal DSP compression may introduce timing and level variations. Uncalibrated."
                )
            }
            AudioRouteType.BUILTIN_SPEAKER -> {
                CalibrationInfo(
                    deviceModel = model,
                    routeType = route,
                    provenance = CalibrationProvenance.UNCALIBRATED,
                    isOfficiallySupported = false,
                    notes = "Speaker output cannot provide left/right ear acoustic isolation. Earphones or headphones are strictly required."
                )
            }
            AudioRouteType.OTHER_UNSUPPORTED -> {
                CalibrationInfo(
                    deviceModel = model,
                    routeType = route,
                    provenance = CalibrationProvenance.UNCALIBRATED,
                    isOfficiallySupported = false,
                    notes = "Audio route is unsupported for audiometric screening."
                )
            }
        }
    }
}

/**
 * Deterministic fake device capability manager for tests and simulation panel.
 */
class FakeDeviceCapabilityManager(
    initialRoute: AudioRouteType = AudioRouteType.WIRED_HEADPHONES,
    private val deviceModelName: String = "Test Device Pixel 8"
) : DeviceCapabilityManager {

    var currentRouteType: AudioRouteType = initialRoute

    override fun getCurrentAudioRoute(): AudioRouteInfo {
        return AudioRouteInfo(
            routeType = currentRouteType,
            deviceName = "Simulated ${currentRouteType.displayName}",
            isStereoCapable = true,
            sampleRateHz = 44100,
            calibrationInfo = getCalibrationStatus(currentRouteType)
        )
    }

    override fun isHeadphoneConnected(): Boolean {
        return currentRouteType.isHeadphone
    }

    override fun getCalibrationStatus(route: AudioRouteType): CalibrationInfo {
        val isSupported = route.isHeadphone
        return CalibrationInfo(
            deviceModel = deviceModelName,
            routeType = route,
            provenance = if (isSupported) CalibrationProvenance.SIMULATED_PROFILE else CalibrationProvenance.UNCALIBRATED,
            isOfficiallySupported = isSupported,
            profileVersion = "SIM-2026",
            notes = if (isSupported) "Simulated headphone profile." else "Unsupported speaker output."
        )
    }
}
