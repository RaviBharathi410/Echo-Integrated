package com.echo.hearing

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.echo.hearing.audio.AndroidAudioTrackStimulusEngine
import com.echo.hearing.data.LocalJsonSessionRepository
import com.echo.hearing.device.AndroidDeviceCapabilityManager
import com.echo.hearing.noise.AndroidMicrophoneNoiseMonitor
import com.echo.hearing.monitor.MonitorViewModel
import com.echo.hearing.ui.EchoApp
import com.echo.hearing.ui.HearingScreeningViewModel
import com.echo.hearing.ui.theme.EchoTheme

class MainActivity : ComponentActivity() {

    private val viewModel: HearingScreeningViewModel by viewModels {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                val stimulusEngine = AndroidAudioTrackStimulusEngine()
                val noiseMonitor = AndroidMicrophoneNoiseMonitor(applicationContext)
                val deviceManager = AndroidDeviceCapabilityManager(applicationContext)
                val sessionRepository = LocalJsonSessionRepository(applicationContext)

                return HearingScreeningViewModel(
                    stimulusEngine = stimulusEngine,
                    noiseMonitor = noiseMonitor,
                    deviceManager = deviceManager,
                    sessionRepository = sessionRepository
                ) as T
            }
        }
    }

    private val monitorViewModel: MonitorViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            EchoTheme {
                val permissionLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.RequestPermission()
                ) { isGranted ->
                    viewModel.onMicrophonePermissionResult(isGranted)
                }

                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    EchoApp(
                        screeningViewModel = viewModel,
                        monitorViewModel = monitorViewModel,
                        onRequestMicrophonePermission = {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    )
                }
            }
        }
    }
}
