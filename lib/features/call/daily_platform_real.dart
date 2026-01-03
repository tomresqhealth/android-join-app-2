import 'package:daily_flutter/daily_flutter.dart' as daily;

/// Real platform bindings to the Daily Flutter plugin. Loaded only on Dart IO
/// platforms (Android/iOS/desktop). Avoids importing the plugin on web.
class DailyPlatform {
  static Future<dynamic> createCallClient() async => daily.CallClient.create();
}
