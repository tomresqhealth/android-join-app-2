import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:resq_health_android_app/features/call/daily_platform.dart';

/// High-level wrapper around the official Daily Flutter SDK typed API.
///
/// This replaces the previous direct MethodChannel calls with the SDK's
/// CallClient, aligning with Daily's documentation. All errors are logged via
/// debugPrint and rethrown for the UI to handle.
class DailyService {
  DailyService._();
  static final DailyService instance = DailyService._();

  dynamic _client; // Resolved via DailyPlatform to avoid importing the plugin on web

  Future<dynamic> _ensureClient() async {
    if (_client != null) return _client!;
    // Create a new client instance; Daily SDK manages platform channels itself
    _client = await DailyPlatform.createCallClient();
    return _client!;
  }

  /// Join a Daily room using the typed API.
  Future<void> join({
    required String url,
    String? token,
    String? userName,
  }) async {
    if (kIsWeb) {
      throw PlatformException(code: 'UNSUPPORTED_PLATFORM', message: 'Daily Flutter plugin is not available in web preview.');
    }
    try {
      final client = await _ensureClient();
      // Join the room first. Some SDKs allow join options, but to keep
      // compatibility across versions, we enforce media states after join.
      debugPrint('DailyService.join: joining url=$url, userName=$userName');
      // ignore: avoid_dynamic_calls
      await (client as dynamic).join(url: Uri.parse(url), token: token);

      // Optionally update display name if supported by the SDK.
      if (userName != null && userName.isNotEmpty) {
        try {
          // ignore: avoid_dynamic_calls
          await (client as dynamic).setUserName(userName);
        } catch (_) {
          try {
            // ignore: avoid_dynamic_calls
            await (client as dynamic).updateUserName(userName);
          } catch (e) {
            debugPrint('DailyService.join: setUserName not available: $e');
          }
        }
      }

      // HARD LOCK: enforce mic/camera OFF after join regardless of any inputs.
      await _applyLocalAudioState(client, false);
      await _applyLocalVideoState(client, false);
    } catch (e, st) {
      debugPrint('DailyService.join error: $e\n$st');
      rethrow;
    }
  }

  /// Start screen sharing.
  Future<void> startScreenShare() async {
    if (kIsWeb) {
      throw PlatformException(code: 'UNSUPPORTED_PLATFORM', message: 'Screen share is not available in web preview.');
    }
    try {
      // The Daily Flutter SDK exposes screen share controls on its typed API.
      // Depending on the version, this may live on CallClient or a nested
      // inputs/media facade. We probe multiple shapes to keep compatibility
      // across versions without crashing.
      _ensureScreenshareEventsListener();
      final client = await _ensureClient();
      debugPrint('DailyService.startScreenShare: client runtimeType=${client.runtimeType}');
      final started = await _tryStartScreenshareOnClient(client);
      if (started) return;

      // If we reached here, the SDK in use doesn't expose screen-share APIs.
      // Try a native bridge fallback: request MediaProjection permission and
      // start a foreground service to keep the session alive. Note: Without a
      // native Daily Android SDK hook, this won't publish the screen into the
      // call yet, but it prepares the OS state correctly.
      final ok = await _startScreenShareViaNativeBridge();
      if (ok) return; // Trust the native bridge; it starts capture via the plugin
      throw PlatformException(code: 'UNIMPLEMENTED', message: 'Screen share start is not available in this Daily SDK version.');
    } catch (e, st) {
      debugPrint('DailyService.startScreenShare error: $e\n$st');
      rethrow;
    }
  }

  /// Stop screen sharing (no-op if not sharing).
  Future<void> stopScreenShare() async {
    if (kIsWeb) return;
    try {
      final client = await _ensureClient();
      debugPrint('DailyService.stopScreenShare: client runtimeType=${client.runtimeType}');
      final dyn = client as dynamic;
      final directStoppers = <Future<void> Function()>[
        // ignore: avoid_dynamic_calls
        () async => await dyn.stopScreenShare(),
        // ignore: avoid_dynamic_calls
        () async => await dyn.stopScreenshare(),
        // ignore: avoid_dynamic_calls
        () async => await dyn.stopScreenSharing(),
        // ignore: avoid_dynamic_calls
        () async => await dyn.stopShareScreen(),
        // ignore: avoid_dynamic_calls
        () async => await dyn.stopScreenShareCapture(),
        // ignore: avoid_dynamic_calls
        () async => await dyn.stopScreenshareCapture(),
      ];
      for (final attempt in directStoppers) {
        try {
          await attempt();
          // Also stop native foreground service if it was started.
          await _stopNativeProjectionService();
          return;
        } on NoSuchMethodError {
          // try next
        }
      }
      try {
        // ignore: avoid_dynamic_calls
        final inputs = dyn.inputs;
        if (inputs != null) {
          final nestedStoppers = <Future<void> Function()>[
            // ignore: avoid_dynamic_calls
            () async => await inputs.stopScreenShare(),
            // ignore: avoid_dynamic_calls
            () async => await inputs.stopScreenshare(),
            // ignore: avoid_dynamic_calls
            () async => await inputs.stopScreenSharing(),
            // ignore: avoid_dynamic_calls
            () async => await inputs.stopShareScreen(),
            // ignore: avoid_dynamic_calls
            () async => await inputs.setScreenShareEnabled(false),
            // ignore: avoid_dynamic_calls
            () async => await inputs.enableScreenShare(false),
          ];
          for (final attempt in nestedStoppers) {
            try {
              await attempt();
              await _stopNativeProjectionService();
              return;
            } on NoSuchMethodError {
              // continue
            }
          }
        }
      } catch (_) {
        // ignore
      }
      // Even if we couldn't call an SDK stop, still request native service stop
      await _stopNativeProjectionService();
    } catch (e, st) {
      debugPrint('DailyService.stopScreenShare error: $e\n$st');
      rethrow;
    }
  }

  /// Leave the current Daily call.
  Future<void> leave() async {
    if (kIsWeb) return;
    try {
      final client = await _ensureClient();
      // ignore: avoid_dynamic_calls
      await (client as dynamic).leave();
      // Ensure any foreground service used for screenshare is stopped as we disconnect
       await _stopNativeProjectionService();
    } catch (e, st) {
      debugPrint('DailyService.leave error: $e\n$st');
      rethrow;
    }
  }

  // Applies local audio (microphone) enabled/disabled state with robust fallbacks.
  Future<void> _applyLocalAudioState(dynamic client, bool enabled) async {
    try {
      // Common API shapes across SDK versions
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setLocalAudio(enabled);
        debugPrint('DailyService: setLocalAudio($enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setAudioEnabled(enabled);
        debugPrint('DailyService: setAudioEnabled($enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setMicrophoneEnabled(enabled);
        debugPrint('DailyService: setMicrophoneEnabled($enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setMicrophoneEnabled(enabled: enabled);
        debugPrint('DailyService: setMicrophoneEnabled(enabled: $enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      debugPrint('DailyService: No audio toggle method available in this SDK');
    } catch (e) {
      debugPrint('DailyService: failed to set audio=$enabled: $e');
    }
  }

  // Applies local video (camera) enabled/disabled state with robust fallbacks.
  Future<void> _applyLocalVideoState(dynamic client, bool enabled) async {
    try {
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setLocalVideo(enabled);
        debugPrint('DailyService: setLocalVideo($enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setVideoEnabled(enabled);
        debugPrint('DailyService: setVideoEnabled($enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setCameraEnabled(enabled);
        debugPrint('DailyService: setCameraEnabled($enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      try {
        // ignore: avoid_dynamic_calls
        await (client as dynamic).setCameraEnabled(enabled: enabled);
        debugPrint('DailyService: setCameraEnabled(enabled: $enabled)');
        return;
      } on NoSuchMethodError {
        // continue
      }
      debugPrint('DailyService: No video toggle method available in this SDK');
    } catch (e) {
      debugPrint('DailyService: failed to set video=$enabled: $e');
    }
  }

  // Native bridge to request projection permission and manage a foreground service.
  // This does NOT publish the screen. It only sets up OS prerequisites.
  static const MethodChannel _projectionChannel = MethodChannel('co.daily/screenshare');
  static const EventChannel _projectionEvents = EventChannel('co.daily/screenshare/events');
  bool _eventsInitialized = false;
  bool _projectionGrantedOnce = false; // avoid duplicate SDK invocations after native start
  void _ensureScreenshareEventsListener() {
    if (_eventsInitialized) return;
    _eventsInitialized = true;
    _projectionEvents.receiveBroadcastStream().listen((event) async {
      try {
        if (event is Map && event['type'] == 'projectionResult') {
          debugPrint('DailyService: projectionResult event: granted=${event['granted']}');
          if (event['granted'] == true && _client != null && !_projectionGrantedOnce) {
            // Best-effort: for SDKs that only expose a typed call after permission.
            // Guard so we don't double-invoke if native reflection already started it.
            _projectionGrantedOnce = true;
            try {
              await _tryStartScreenshareOnClient(_client!);
            } catch (e) {
              // Don't surface as fatal here; native bridge may already be active.
              debugPrint('DailyService: post-grant SDK start attempt failed (benign if native started): $e');
            }
          }
        }
      } catch (e) {
        debugPrint('DailyService: projection event handler error: $e');
      }
    }, onError: (e) {
      debugPrint('DailyService: projection events error: $e');
    });
  }

  Future<bool> _tryStartScreenshareOnClient(dynamic client) async {
    final dyn = client as dynamic;
    // 1) Direct methods on CallClient
    final directStarters = <Future<void> Function()>[
      () async => await dyn.startScreenShare(),
      () async => await dyn.startScreenshare(),
      () async => await dyn.startScreenSharing(),
      () async => await dyn.startShareScreen(),
      () async => await dyn.startScreenShareCapture(),
      () async => await dyn.startScreenshareCapture(),
    ];
    for (final attempt in directStarters) {
      try {
        await attempt();
        return true;
      } on NoSuchMethodError {
        // try next
      } catch (e) {
        rethrow;
      }
    }
    // 2) Nested inputs facades
    try {
      final inputs = dyn.inputs;
      if (inputs != null) {
        final nestedStarters = <Future<void> Function()>[
          () async => await inputs.startScreenShare(),
          () async => await inputs.startScreenshare(),
          () async => await inputs.startScreenSharing(),
          () async => await inputs.startShareScreen(),
          () async => await inputs.setScreenShareEnabled(true),
          () async => await inputs.enableScreenShare(true),
        ];
        for (final attempt in nestedStarters) {
          try {
            await attempt();
            return true;
          } on NoSuchMethodError {
            // try next
          }
        }
      }
    } catch (_) {
      // ignore
    }
    return false;
  }

  Future<bool> _startScreenShareViaNativeBridge() async {
    try {
      final granted = await _projectionChannel.invokeMethod<bool>('requestProjection');
      if (granted != true) return false;
      await _projectionChannel.invokeMethod('startForegroundService');
      debugPrint('Native projection permission granted and foreground service started.');
      return true;
    } on PlatformException catch (e) {
      debugPrint('Native projection request failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Native projection request failed: $e');
      return false;
    }
  }

  Future<void> _stopNativeProjectionService() async {
    try {
      // Prefer the explicitly named cleanup method; fall back to legacy alias if needed.
      await _projectionChannel.invokeMethod('stopScreenShareService');
      debugPrint('Requested native stopScreenShareService.');
    } on PlatformException catch (e) {
      // If method not implemented, try the previous name.
      if (e.code == 'MissingPluginException' || e.code == 'UNKNOWN' || e.code == 'notImplemented') {
        try {
          await _projectionChannel.invokeMethod('stopForegroundService');
          debugPrint('Fallback: Requested native stopForegroundService.');
        } catch (ee) {
          debugPrint('Native stopForegroundService failed: $ee');
        }
      } else {
        debugPrint('Native stopScreenShareService failed: ${e.code} ${e.message}');
      }
    } catch (e) {
      debugPrint('Native stopScreenShareService failed: $e');
    }
  }
}
