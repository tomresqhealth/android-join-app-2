import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:resq_health_android_app/nav.dart';
import 'package:resq_health_android_app/theme.dart';
import 'package:resq_health_android_app/widgets/app_version_label.dart';

class JoinRoomPage extends StatefulWidget {
  const JoinRoomPage({super.key});

  @override
  State<JoinRoomPage> createState() => _JoinRoomPageState();
}

class _JoinRoomPageState extends State<JoinRoomPage> {
  final _formKey = GlobalKey<FormState>();
  final _roomUrlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  static const String _defaultRoomUrl =
      'https://resqhealth.daily.co/resq-training-center-1';
  static const String _defaultDisplayName = 'Tablet';

  @override
  void initState() {
    super.initState();
    // Pre-fill with the provided Daily.co room URL
    _roomUrlCtrl.text = _defaultRoomUrl;
    // Pre-fill a sensible display name so user can just tap Join
    _nameCtrl.text = _defaultDisplayName;
  }

  @override
  void dispose() {
    _roomUrlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _join() {
    // In Dreamflow Preview (web), the native Daily plugin isn't available.
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screen sharing isn\'t available in web preview. Please run on an Android tablet to join.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    // Directly join with pre-configured values. Mic/Camera are hard-disabled.
    context.push(AppRoutes.call, extra: {
      'roomUrl': _defaultRoomUrl,
      'name': _defaultDisplayName,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Tablet Screen'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: AppSpacing.paddingXl,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 120),
                      shape: const StadiumBorder(),
                      splashFactory: NoSplash.splashFactory,
                      textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    icon: const Icon(Icons.screen_share_outlined, size: 36),
                    onPressed: _join,
                    label: const Text('Share Screen'),
                  ),
                ),
                const SizedBox(height: 12),
                const AppVersionLabel(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

