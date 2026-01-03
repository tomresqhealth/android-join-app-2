import 'package:resq_health_android_app/main.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:resq_health_android_app/features/call/join_room_page.dart';
import 'package:resq_health_android_app/features/call/call_page.dart';

/// GoRouter configuration for app navigation
///
/// This uses go_router for declarative routing, which provides:
/// - Type-safe navigation
/// - Deep linking support (web URLs, app links)
/// - Easy route parameters
/// - Navigation guards and redirects
///
/// To add a new route:
/// 1. Add a route constant to AppRoutes below
/// 2. Add a GoRoute to the routes list
/// 3. Navigate using context.go() or context.push()
/// 4. Use context.pop() to go back.
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.join,
    routes: [
      GoRoute(
        path: AppRoutes.join,
        name: 'join',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: JoinRoomPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.call,
        name: 'call',
        pageBuilder: (context, state) {
          final extras = state.extra as Map<String, dynamic>?;
          final roomUrl = extras?['roomUrl'] as String? ?? '';
          final name = extras?['name'] as String? ?? '';
          return NoTransitionPage(
            child: CallPage(
              roomUrl: roomUrl,
              displayName: name,
            ),
          );
        },
      ),
      // Keep the starter home page accessible at '/home'
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MyHomePage(title: 'Dreamflow Starter Project'),
        ),
      ),
    ],
  );
}

/// Route path constants
/// Use these instead of hard-coding route strings
class AppRoutes {
  static const String home = '/';
  static const String join = '/join';
  static const String call = '/call';
}
