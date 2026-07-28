// Reproduces https://github.com/flutter/flutter/issues/188993
//
// `GoRouterDelegate._findCurrentNavigators` (delegate.dart:126) force-unwraps
// `walker.navigatorKey.currentState!` for every `ShellRouteMatch` in the
// current configuration. Any moment in which the configuration already holds a
// shell match while that shell's `Navigator` is not in the tree turns a back
// press into `Null check operator used on a null value`.
//
// `WidgetsBinding.handlePopRoute` swallows that exception and falls through to
// `SystemNavigator.pop()`, so what the user sees is the back button closing
// the app instead of navigating.
//
// See README.md for the three ways this app gets into that state.

import 'package:flutter/material.dart';

import 'src/crash_reporter.dart';
import 'src/router.dart';
import 'src/screens/crash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CrashReporter.install();
  await CrashReporter.loadPreviousRun();
  runApp(const ReproApp());
}

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'flutter/flutter#188993',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      routerConfig: router,
      builder: (BuildContext context, Widget? child) => Stack(
        children: <Widget>[
          ?child,
          const CrashOverlay(),
        ],
      ),
    );
  }
}
