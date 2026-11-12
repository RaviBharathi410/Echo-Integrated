package com.echo.hearing

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var audioPlugin: EchoAudioPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioPlugin = EchoAudioPlugin(applicationContext).also { plugin ->
            plugin.registerWith(flutterEngine)
        }
    }

    override fun onStop() {
        audioPlugin?.coordinator?.releaseAllAudio("backgrounded")
        super.onStop()
    }

    override fun onDestroy() {
        audioPlugin?.dispose()
        audioPlugin = null
        super.onDestroy()
    }
}

