import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/app_shell.dart';
import 'screens/sign_in_screen.dart';
import 'screens/tab_screens.dart';

/// The key whose `currentState` is force-unwrapped by
/// `GoRouterDelegate._findCurrentNavigators` (delegate.dart:126).
final GlobalKey<NavigatorState> shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (_, _) => const SignInScreen()),
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      // `child` is the Navigator that go_router built for this shell. AppShell
      // only puts it in the tree once the session has been restored.
      builder: (_, _, Widget child) => AppShell(child: child),
      routes: <RouteBase>[
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      ],
    ),
  ],
);
