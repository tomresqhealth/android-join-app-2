import 'package:flutter/services.dart';

/// Stub bindings used on web where the Daily Flutter plugin isn't available.
class DailyPlatform {
  static Future<dynamic> createCallClient() async {
    throw PlatformException(
      code: 'UNSUPPORTED_PLATFORM',
      message: 'Daily Flutter plugin is not available on web.',
    );
  }
}
