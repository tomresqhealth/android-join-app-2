package com.resqhealth.jointablet

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val channelName = "co.daily/screenshare"
    private val eventsChannelName = "co.daily/screenshare/events"
    private val requestCodeProjection = 8301

    private var pendingProjectionResult: MethodChannel.Result? = null
    private var eventsSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "requestProjection" -> {
                    requestProjection(result)
                }
                "startForegroundService" -> {
                    startProjectionService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopProjectionService()
                    result.success(true)
                }
                // Alias more clearly named for Flutter side cleanup calls
                "stopScreenShareService" -> {
                    stopProjectionService()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventsSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventsSink = null
            }
        })
    }

    private fun requestProjection(result: MethodChannel.Result) {
        if (pendingProjectionResult != null) {
            // Only one request at a time
            result.error("BUSY", "Another projection request is in progress", null)
            return
        }
        val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = mgr.createScreenCaptureIntent()
        pendingProjectionResult = result
        startActivityForResult(intent, requestCodeProjection)
    }

    private fun startProjectionService() {
        val svcIntent = Intent(this, ScreenShareService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(svcIntent)
        } else {
            startService(svcIntent)
        }
    }

    private fun stopProjectionService() {
        val svcIntent = Intent(this, ScreenShareService::class.java)
        stopService(svcIntent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestCodeProjection) {
            val callback = pendingProjectionResult
            pendingProjectionResult = null
            if (callback == null) return

            if (resultCode == Activity.RESULT_OK && data != null) {
                // Order of operations for modern Android:
                // 1) We have the Intent result (granted)
                // 2) Start foreground service with mediaProjection type
                // 3) Call Daily SDK with the Intent
                startProjectionService()
                // We no longer try to reflect into the Daily plugin here. Instead, we
                // start a foreground service to keep the process alive during capture,
                // and notify Dart. The Dart side will invoke the plugin's official
                // screen-share API after permission is granted.
                callback.success(true)
                // Also broadcast an event so Flutter-side can react if needed.
                eventsSink?.success(mapOf(
                    "type" to "projectionResult",
                    "granted" to true
                ))
            } else {
                callback.error("USER_DENIED", "User denied screen capture permission", null)
                eventsSink?.success(mapOf(
                    "type" to "projectionResult",
                    "granted" to false
                ))
            }
        }
    }

    // Intentionally removed all reflection-based attempts to invoke the Daily plugin.
    // The Flutter/Dart layer will call the plugin's official API after this Activity
    // signals that projection permission was granted.
}

