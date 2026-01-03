import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:resq_health_android_app/theme.dart';
import 'package:resq_health_android_app/features/call/daily_service.dart';
import 'package:resq_health_android_app/widgets/app_version_label.dart';

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.roomUrl, required this.displayName});
  final String roomUrl;
  final String displayName;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  // Daily service wrapper
  final DailyService _daily = DailyService.instance;
  bool _joining = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      if (kIsWeb) {
        debugPrint('Join skipped on web: Daily native plugin not available.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join is not supported in web preview. Please run on an Android tablet.')),
          );
        }
        return;
      }
      await _daily.join(
        url: widget.roomUrl,
        token: null,
        userName: widget.displayName,
      );
      // Auto-start screen sharing right after a successful join.
      // Android will show a system dialog the first time; user must accept.
      await _shareScreen();
    } catch (e) {
      debugPrint('Daily join failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Join failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _shareScreen() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Screen sharing is not supported in web preview. Run on Android.')),
          );
        }
        return;
      }
      await _daily.startScreenShare();
    } catch (e) {
      debugPrint('startScreenShare failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Screen share failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _leave() async {
    try {
      await _daily.leave();
    } catch (e) {
      debugPrint('Leave failed: $e');
    } finally {
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomUrl),
        actions: [
          IconButton(
            onPressed: _joining ? null : _shareScreen,
            icon: const Icon(Icons.ios_share),
            color: cs.onPrimary,
            tooltip: 'Share Screen',
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Leave'),
            style: TextButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
          ),
          const SizedBox(width: 12),
        ],
        centerTitle: true,
      ),
      body: Center(
        child: _joining
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups, size: 100, color: cs.primary),
                  const SizedBox(height: 16),
                  const Text('You are connected to the call.'),
                  const SizedBox(height: 8),
                  const Text('Mic: OFF • Cam: OFF'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.ios_share, color: Colors.white),
                    onPressed: _shareScreen,
                    label: Text(_sharing ? 'Sharing…' : 'Share Screen'),
                  ),
                  const SizedBox(height: 8),
                  const AppVersionLabel(),
                ],
              ),
      ),
    );
  }
}
