package com.echo.hearing

import android.content.Context
import com.echo.hearing.monitor.NativeAudioEngine
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Thin Flutter platform plugin wrapping AudioSessionCoordinator and NativeAudioEngine JNI.
 */
class EchoAudioPlugin(
    private val context: Context
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val CONTROL_CHANNEL = "com.echo.hearing/audio_control"
        const val EVENTS_CHANNEL = "com.echo.hearing/audio_events"
    }

    private var eventSink: EventChannel.EventSink? = null
    val coordinator: AudioSessionCoordinator by lazy {
        AudioSessionCoordinator(context) { event ->
            eventSink?.success(event)
        }
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, CONTROL_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENTS_CHANNEL).setStreamHandler(this)
        // Ensure coordinator and AudioDeviceCallback initialize once attached.
        coordinator
    }

    fun dispose() {
        coordinator.dispose()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startMonitor" -> {
                    val inputId = call.argument<Int>("inputId") ?: -1
                    val outputId = call.argument<Int>("outputId") ?: -1
                    val level = (call.argument<Number>("level")?.toFloat()) ?: 0.15f
                    result.success(coordinator.startMonitor(inputId, outputId, level))
                }
                "stopMonitor" -> {
                    val reason = call.argument<String>("reason") ?: "user"
                    val message = call.argument<String>("message") ?: "Stopped"
                    coordinator.stopMonitor(reason, message)
                    result.success(null)
                }
                "setMonitorLevel" -> {
                    val level = (call.argument<Number>("level")?.toFloat()) ?: 0.15f
                    NativeAudioEngine.nativeSetMonitorLevel(level.coerceIn(0f, 0.5f))
                    result.success(null)
                }
                "setEqualizerBand" -> {
                    val ear = call.argument<Int>("ear") ?: 0
                    val band = call.argument<Int>("band") ?: 0
                    val gainDb = (call.argument<Number>("gainDb")?.toFloat()) ?: 0f
                    NativeAudioEngine.nativeSetEqualizerBand(ear, band, gainDb.coerceIn(-6f, 6f))
                    result.success(null)
                }
                "setSpeechCompression" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val ratio = (call.argument<Number>("ratio")?.toFloat()) ?: 2.0f
                    NativeAudioEngine.nativeSetSpeechCompressionEnabled(enabled)
                    NativeAudioEngine.nativeSetSpeechCompressionRatio(ratio.coerceIn(1f, 3f))
                    result.success(null)
                }
                "setNoiseGate" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val thresholdDb = (call.argument<Number>("thresholdDb")?.toFloat()) ?: -54f
                    NativeAudioEngine.nativeSetNoiseGateEnabled(enabled)
                    NativeAudioEngine.nativeSetNoiseGateThresholdDb(thresholdDb.coerceIn(-72f, -36f))
                    result.success(null)
                }
                "setAdaptiveDenoiser" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val strengthDb = (call.argument<Number>("strengthDb")?.toFloat()) ?: 9f
                    NativeAudioEngine.nativeSetAdaptiveDenoiserEnabled(enabled)
                    NativeAudioEngine.nativeSetAdaptiveDenoiserStrengthDb(strengthDb.coerceIn(0f, 18f))
                    result.success(null)
                }
                "setDspBypassed" -> {
                    val bypassed = call.argument<Boolean>("bypassed") ?: false
                    NativeAudioEngine.nativeSetDspBypassed(bypassed)
                    result.success(null)
                }
                "isMonitorRunning" -> result.success(NativeAudioEngine.nativeIsRunning())
                "getMonitorStreamInfo" -> result.success(NativeAudioEngine.nativeGetStreamInfo())
                "getMonitorDevices" -> result.success(coordinator.getMonitorDevicesMap())
                "getScreeningAudioRoute" -> result.success(coordinator.deviceManager.getCurrentScreeningRouteMap())
                "startNoiseMonitor" -> result.success(coordinator.startNoiseMonitor())
                "stopNoiseMonitor" -> {
                    coordinator.stopNoiseMonitor()
                    result.success(null)
                }
                "isNoiseSensorAvailable" -> result.success(coordinator.isNoiseSensorAvailable())
                "playTone" -> {
                    val freq = call.argument<Int>("frequencyHz") ?: 1000
                    val levelDb = call.argument<Int>("levelDb") ?: 40
                    val ear = call.argument<String>("ear") ?: "LEFT"
                    val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 1200L
                    result.success(coordinator.playTone(freq, levelDb, ear, durationMs))
                }
                "stopTone" -> {
                    coordinator.stopTone("interrupted")
                    result.success(null)
                }
                "isTonePlaying" -> result.success(coordinator.isTonePlaying())
                "releaseAllAudio" -> {
                    val reason = call.argument<String>("reason") ?: "backgrounded"
                    coordinator.releaseAllAudio(reason)
                    result.success(null)
                }
                "readLegacyPrefs" -> {
                    result.success(readLegacyPreferences())
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ECHO_AUDIO_ERROR", e.message, null)
        }
    }

    private fun readLegacyPreferences(): Map<String, Map<String, Any?>> {
        val userPrefs = context.getSharedPreferences("echo_user_profile", Context.MODE_PRIVATE).all
        val monitorPrefs = context.getSharedPreferences("echo_profile", Context.MODE_PRIVATE).all
        return mapOf(
            "echo_user_profile" to userPrefs,
            "echo_profile" to monitorPrefs
        )
    }
}

