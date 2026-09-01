// Reproduces https://github.com/flutter/flutter/issues/188993 on Android:
// tap "Sign in", then press the system back button while "Restoring session"
// is on screen.

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const Duration sessionRestoreDelay = Duration(seconds: 5);

final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, _) => const SignInScreen()),
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

void main() {
  // The activity is closed right after the error is reported, before
  // debugPrint's throttled output would get through.
  FlutterError.onError = (FlutterErrorDetails details) {
    print(details.exception);
    print(details.stack);
  };
  runApp(MaterialApp.router(routerConfig: router));
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          // push rather than go, so the sign in screen stays underneath. With
          // predictive back (Android 13+) the engine only forwards the back
          // button to Dart while the framework reports it can pop.
          onPressed: () => router.push('/dashboard'),
          child: const Text('Sign in'),
        ),
      ),
    );
  }
}

/// Shows a loading screen instead of [child] until the session is restored.
///
/// For as long as it does, `currentConfiguration.matches.last` is the
/// `ShellRouteMatch` while `shellNavigatorKey.currentState` is null.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final Timer _restore;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restore = Timer(sessionRestoreDelay, () => setState(() => _ready = true));
  }

  @override
  void dispose() {
    _restore.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: Text('Restoring session, press back now')),
      );
    }
    return Scaffold(body: widget.child);
  }
}
