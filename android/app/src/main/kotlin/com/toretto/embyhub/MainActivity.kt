package com.toretto.embyhub

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val pipChannelName = "app.pip"
    private val platformChannelName = "com.embyhub/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // PIP 功能通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> {
                    enterPip()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // 平台功能通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBackground" -> {
                    // 将应用移到后台（不退出）
                    moveTaskToBack(true)
                    result.success(true)
                }
                "setHighRefreshRate" -> {
                    setHighRefreshRate()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        }
    }

    private fun setHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }

        val displayCompat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }

        if (displayCompat == null) {
            return
        }

        val bestMode = displayCompat.supportedModes.maxByOrNull { it.refreshRate }
        if (bestMode != null) {
            val params = window.attributes
            if (params.preferredDisplayModeId != bestMode.modeId) {
                params.preferredDisplayModeId = bestMode.modeId
                window.attributes = params
            }
        }
    }
}

