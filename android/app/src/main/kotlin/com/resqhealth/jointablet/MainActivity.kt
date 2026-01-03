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
                // Best-effort: forward the projection intent directly to the Daily plugin
                // so the SDK can start publishing the screen.
                tryPassIntentToDailyPlugin(data)
                // We cannot marshal the Intent itself to Dart. The expectation is that
                // native SDK handles the projection using this permission. For now,
                // we return success=true to indicate permission granted.
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

    /**
     * Attempts to locate the Daily Flutter plugin instance or its CallClient/inputs and
     * invoke a screen-share start method using the granted MediaProjection permission.
     *
     * Tries a wider set of possibilities to handle API variations across plugin versions:
     *  - CallClient.startScreenShare(Intent)
     *  - CallClient.startScreenShare(Context, Intent)
     *  - inputs.startScreenShare(Intent)
     *  - inputs.startScreenShare(Context, Intent)
     *  - DailyFlutterPlugin.startScreenShare(Intent)
     *  - DailyFlutterPlugin.startScreenShare(Context, Intent)
     *
     * This uses guarded reflection because the plugin types are not exposed here
     * and may vary across versions. All failures are logged and safely ignored.
     */
    private fun tryPassIntentToDailyPlugin(data: Intent) {
        val engine: FlutterEngine? = flutterEngine
        if (engine == null) {
            Log.w("MainActivity", "No FlutterEngine when trying to pass projection intent to Daily plugin")
            return
        }
        try {
            // 1) Try to get the plugin registry via the public API first, then fall back to fields
            // so we don't depend on private field names across Flutter versions.
            val getPluginsMethod = FlutterEngine::class.java.methods.firstOrNull { m ->
                m.name == "getPlugins" && m.parameterTypes.isEmpty()
            }
            var registry: Any? = null
            try {
                if (getPluginsMethod != null) registry = getPluginsMethod.invoke(engine)
            } catch (_: Throwable) {
                // ignore and try private fields fallback below
            }
            if (registry == null) {
                // Fallback: probe for any field that looks like a plugin registry container
                val candidateField = FlutterEngine::class.java.declaredFields.firstOrNull { f ->
                    f.name.contains("plugins", ignoreCase = true)
                }
                if (candidateField != null) {
                    candidateField.isAccessible = true
                    registry = candidateField.get(engine)
                }
            }
            if (registry == null) {
                Log.w("MainActivity", "No plugin registry available on FlutterEngine; cannot locate Daily plugin")
                return
            }

            // Preferred fully-qualified names to try for the plugin class.
            val candidatePluginClassNames = listOf(
                "co.daily.daily_flutter.DailyFlutterPlugin",
                "co.daily.flutter.DailyFlutterPlugin",
                "co.daily.DailyFlutterPlugin"
            )

            var pluginInstance: Any? = null
            var pluginClass: Class<*>? = null

            // Try path A: registry.get(Class)
            val getMethod = registry::class.java.methods.firstOrNull { m ->
                m.name == "get" && m.parameterTypes.size == 1 && m.parameterTypes[0] == Class::class.java
            }
            if (getMethod != null) {
                for (name in candidatePluginClassNames) {
                    try {
                        val clazz = Class.forName(name)
                        val inst = getMethod.invoke(registry, clazz)
                        if (inst != null) {
                            pluginInstance = inst
                            pluginClass = clazz
                            break
                        }
                    } catch (_: Throwable) {
                        // continue to next candidate
                    }
                }
            }

            // Try path B: inspect collection fields on the registry to find a matching plugin instance
            if (pluginInstance == null) {
                try {
                    val registryFields = registry::class.java.declaredFields
                    for (f in registryFields) {
                        try {
                            f.isAccessible = true
                            val value = f.get(registry) ?: continue
                            if (value is Iterable<*>) {
                                for (p in value) {
                                    val cn = p?.javaClass?.name ?: continue
                                    if (candidatePluginClassNames.any { cn == it }) {
                                        pluginInstance = p
                                        pluginClass = p.javaClass
                                        break
                                    }
                                }
                                if (pluginInstance != null) break
                            }
                        } catch (_: Throwable) { }
                    }
                } catch (_: Throwable) {
                }
            }

            if (pluginInstance == null) {
                Log.w("MainActivity", "DailyFlutterPlugin instance not found in registry; skipping native startScreenShare")
                return
            }

            // 2) From the plugin, try to obtain a CallClient instance via a common accessor.
            // Look for either getCallClient() or a 'callClient' field.
            var callClient: Any? = null
            try {
                val getter = pluginClass!!.methods.firstOrNull { it.name == "getCallClient" && it.parameterTypes.isEmpty() }
                if (getter != null) {
                    callClient = getter.invoke(pluginInstance)
                }
            } catch (_: Throwable) {
            }
            if (callClient == null) {
                try {
                    val field = pluginClass!!.declaredFields.firstOrNull { it.name == "callClient" }
                    if (field != null) {
                        field.isAccessible = true
                        callClient = field.get(pluginInstance)
                    }
                } catch (_: Throwable) {
                }
            }

            if (callClient == null) {
                Log.w("MainActivity", "DailyFlutterPlugin has no accessible CallClient; skipping native startScreenShare")
                // Don't return yet; we'll still try invoking on the plugin itself below.
            }

            // Helper lambdas for invoking start methods on arbitrary targets with different signatures
            val tryInvokeWithIntentOnly: (Any, List<String>) -> Boolean = { target, names ->
                try {
                    val method = target::class.java.methods.firstOrNull { m ->
                        names.any { cand -> m.name.startsWith(cand) } &&
                            m.parameterTypes.size == 1 &&
                            Intent::class.java.isAssignableFrom(m.parameterTypes[0])
                    }
                    if (method != null) {
                        method.invoke(target, data)
                        true
                    } else false
                } catch (t: Throwable) {
                    Log.w("MainActivity", "Invoke with (Intent) failed on ${target::class.java.name}: ${t.message}")
                    false
                }
            }

            val tryInvokeWithContextAndIntent: (Any, List<String>) -> Boolean = { target, names ->
                try {
                    val method = target::class.java.methods.firstOrNull { m ->
                        names.any { cand -> m.name.startsWith(cand) } &&
                            m.parameterTypes.size == 2 &&
                            Context::class.java.isAssignableFrom(m.parameterTypes[0]) &&
                            Intent::class.java.isAssignableFrom(m.parameterTypes[1])
                    }
                    if (method != null) {
                        method.invoke(target, this@MainActivity, data)
                        true
                    } else false
                } catch (t: Throwable) {
                    Log.w("MainActivity", "Invoke with (Context, Intent) failed on ${target::class.java.name}: ${t.message}")
                    false
                }
            }

            val nameCandidates = listOf(
                "startScreenShare",
                "startScreenshare",
                "startScreenSharing",
                "startShareScreen",
                // some SDKs might use more explicit names
                "startAndroidScreenShare",
                "startScreenShareAndroid"
            )

            // 3) Invoke on the CallClient (Intent) or (Context, Intent)
            try {
                if (callClient != null) {
                    if (tryInvokeWithIntentOnly(callClient, nameCandidates)) {
                        Log.i("MainActivity", "Invoked CallClient.startScreenShare(Intent) via Daily plugin")
                        return
                    }
                    if (tryInvokeWithContextAndIntent(callClient, nameCandidates)) {
                        Log.i("MainActivity", "Invoked CallClient.startScreenShare(Context, Intent) via Daily plugin")
                        return
                    }
                }
            } catch (e: Throwable) {
                Log.w("MainActivity", "Failed to invoke CallClient.startScreenShare(Intent): ${e.message}")
            }

            // 4) Alternative shapes: a nested 'inputs' facade
            try {
                val inputsGetter = callClient?.let { cc -> cc::class.java.methods.firstOrNull { it.name == "getInputs" && it.parameterTypes.isEmpty() } }
                val inputs = if (callClient != null) inputsGetter?.invoke(callClient) else null
                if (inputs != null) {
                    if (tryInvokeWithIntentOnly(inputs, nameCandidates)) {
                        Log.i("MainActivity", "Invoked inputs.startScreenShare(Intent) via Daily plugin")
                        return
                    }
                    if (tryInvokeWithContextAndIntent(inputs, nameCandidates)) {
                        Log.i("MainActivity", "Invoked inputs.startScreenShare(Context, Intent) via Daily plugin")
                        return
                    }
                }
            } catch (_: Throwable) {
            }

            // 5) As a last resort, try invoking directly on the plugin instance
            try {
                if (pluginInstance != null) {
                    if (tryInvokeWithIntentOnly(pluginInstance!!, nameCandidates)) {
                        Log.i("MainActivity", "Invoked plugin.startScreenShare(Intent) via Daily plugin")
                        return
                    }
                    if (tryInvokeWithContextAndIntent(pluginInstance!!, nameCandidates)) {
                        Log.i("MainActivity", "Invoked plugin.startScreenShare(Context, Intent) via Daily plugin")
                        return
                    }
                }
            } catch (_: Throwable) {
            }

            Log.w("MainActivity", "No matching startScreenShare method found on plugin/CallClient/inputs")
        } catch (t: Throwable) {
            Log.w("MainActivity", "Error while trying to route projection intent to Daily plugin: ${t.message}")
        }
    }
}

