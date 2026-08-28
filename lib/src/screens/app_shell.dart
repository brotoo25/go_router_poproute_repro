import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../session.dart';

/// The `ShellRoute` body.
///
/// The crash window is exactly the period in which this widget returns
/// something other than [child]: go_router's configuration already contains the
/// `ShellRouteMatch`, but the `Navigator` behind `shellNavigatorKey` is not in
/// the tree, so `navigatorKey.currentState` is null.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, super.key});

  /// The `Navigator` go_router built for this shell.
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    Session.instance.beginRestore();
  }

  int _indexFor(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    return location.startsWith('/settings') ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (BuildContext context, _) {
        if (!Session.instance.isReady) {
          return const _RestoringSessionScreen();
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Acme')),
          body: widget.child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _indexFor(context),
            onDestinationSelected: (int index) =>
                context.go(index == 0 ? '/dashboard' : '/settings'),
            destinations: const <Widget>[
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RestoringSessionScreen extends StatelessWidget {
  const _RestoringSessionScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Restoring session',
              key: const Key('restoring-session'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Press back now to reproduce'),
          ],
        ),
      ),
    );
  }
}
