// Reproduces https://github.com/flutter/flutter/issues/188993
//
// go() updates GoRouterDelegate.currentConfiguration synchronously, but the
// ShellRoute's Navigator only mounts on the next frame. A popRoute (back
// button) event delivered inside that window hits the null check in
// _findCurrentNavigators (delegate.dart:126) and throws.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> shellNavigatorKey =
    GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (_, _, Widget child) => child,
      routes: <RouteBase>[
        GoRoute(
          path: '/dashboard',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('Dashboard'))),
        ),
      ],
    ),
  ],
);

void main() {
  runApp(MaterialApp.router(routerConfig: router));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const bool autoRepro = bool.fromEnvironment('AUTO_REPRO');

  String _status = '';

  @override
  void initState() {
    super.initState();
    if (autoRepro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer(const Duration(seconds: 2), _reproduceSynthetic);
      });
    }
  }

  void _logTransientState() {
    final RouteMatchList config = router.routerDelegate.currentConfiguration;
    debugPrint('currentConfiguration.uri: ${config.uri}');
    debugPrint(
      'currentConfiguration.matches.last is ShellRouteMatch: '
      '${config.matches.last is ShellRouteMatch}',
    );
    debugPrint(
      'shell navigator mounted: ${shellNavigatorKey.currentState != null}',
    );
  }

  void _reproduceSynthetic() {
    router.go('/dashboard');
    _logTransientState();
    debugPrint('delivering popRoute (hardware back) before the next frame...');
    // Same message the engine sends when the hardware back button is
    // pressed, delivered before the frame that mounts the shell navigator.
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec
          .encodeMethodCall(const MethodCall('popRoute')),
      (ByteData? _) {},
    );
  }

  void _armBackgroundNavigation() {
    setState(
      () => _status = 'Armed. Background the app now (home button).\n'
          'In 3 seconds it will navigate to /dashboard while paused.\n'
          'Then reopen the app and IMMEDIATELY press the hardware back '
          'button.\n(The window lasts until the first frame after resume, '
          'so it may take a couple of attempts.)',
    );
    // No frames are produced while the app is paused, so this leaves the
    // shell navigator unmounted until the first frame after resume.
    Timer(const Duration(seconds: 3), () {
      router.go('/dashboard');
      _logTransientState();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter/flutter#188993')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton(
              onPressed: _reproduceSynthetic,
              child: const Text('Reproduce (synthetic back event)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _armBackgroundNavigation,
              child: const Text('Arm background navigation (real back button)'),
            ),
            const SizedBox(height: 24),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
