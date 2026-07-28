// Minimal reproduction for flutter/flutter#188993 / flutter/packages#12111.
//
// Self-contained: go_router is the only dependency. Run on Android, because
// the crash is triggered by the system back button.
//
//   flutter run -t lib/minimal_repro.dart -d <android-device>
//
// 1. Tap "Sign in".
// 2. While "Restoring session" is on screen, press the system back button.
//
// Expected: back returns to the sign in screen.
// Actual:   GoRouterDelegate.popRoute throws `Null check operator used on a
//           null value` at delegate.dart:126. WidgetsBinding.handlePopRoute
//           catches it and falls through to SystemNavigator.pop(), so the
//           back button closes the app.

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The key whose `currentState` `_findCurrentNavigators` force-unwraps.
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Center(
          child: FilledButton(
            // push, not go: the engine only forwards the back button to Dart
            // when something is poppable. With a single root page Android
            // consumes the press itself and go_router never sees it.
            onPressed: () => router.push('/dashboard'),
            child: const Text('Sign in'),
          ),
        ),
      ),
    ),
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (_, _, Widget child) => AppShell(child: child),
      routes: <RouteBase>[
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Center(child: Text('Dashboard')),
        ),
      ],
    ),
  ],
);

/// A shell that does async startup work before it can render.
///
/// While that work is in flight the shell returns a loading screen *instead of*
/// [child], which is the `Navigator` go_router built for this `ShellRoute`.
/// That is the whole reproduction:
///
///   currentConfiguration.matches.last -> ShellRouteMatch   (already active)
///   shellNavigatorKey.currentState    -> null              (not in the tree)
///
/// Refreshing an auth token, opening a database, reading secure storage,
/// fetching remote config: any of them puts a shell here, for as long as they
/// take rather than for a single frame.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _ready = true);
      }
    });

    // Shows the state the reviewer asked about, before any back press.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RouteMatchBase last =
          router.routerDelegate.currentConfiguration.matches.last;
      debugPrint('matches.last                   : ${last.runtimeType}');
      debugPrint('shellNavigatorKey.currentState : '
          '${shellNavigatorKey.currentState}');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: Text('Restoring session — press back now')),
      );
    }
    return Scaffold(body: widget.child);
  }
}

void main() {
  // print(), not debugPrint(): SystemNavigator.pop() finishes the activity a
  // few statements after the error is reported, and debugPrint's throttled
  // output does not survive that. Without this the app just disappears.
  FlutterError.onError = (FlutterErrorDetails details) {
    print('---- FlutterError.onError ----');
    print(details.exception);
    print(details.stack);
  };
  runApp(MaterialApp.router(routerConfig: router));
}
