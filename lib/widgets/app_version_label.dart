import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Displays the app version below actions or buttons.
/// Uses PackageInfo to read version name and build number.
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key, this.alignment = TextAlign.center});

  /// Text alignment, defaults to center for button/footer placement.
  final TextAlign alignment;

  static final Future<PackageInfo> _infoFuture = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);

    // In Dreamflow web preview, some plugins may not be registered. Show a friendly fallback.
    if (kIsWeb) {
      return Text('Preview build', textAlign: alignment, style: baseStyle);
    }

    return FutureBuilder<PackageInfo>(
      future: _infoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('…', textAlign: alignment, style: baseStyle);
        }
        if (snapshot.hasError) {
          debugPrint('AppVersionLabel error: ${snapshot.error}');
          return Text('Version unavailable', textAlign: alignment, style: baseStyle);
        }
        final info = snapshot.data;
        if (info == null) return Text('Version unavailable', textAlign: alignment, style: baseStyle);
        final versionText = 'v${info.version} (build ${info.buildNumber})';
        return Text(versionText, textAlign: alignment, style: baseStyle);
      },
    );
  }
}
