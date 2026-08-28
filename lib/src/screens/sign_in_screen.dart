import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crash_reporter.dart';
import '../router.dart';
import '../session.dart';

/// Entry point of the app and the control panel for the three ways to land in
/// the crash window.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  AppLifecycleListener? _lifecycle;
  String _hint = '';

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Scenario 1 — the realistic one.
  ///
  /// A normal sign in that lands on a shell route whose body is still
  /// restoring the session. Every back press until the shell finishes hits
  /// the unmounted navigator.
  void _signIn() {
    CrashReporter.clear();
    Session.instance.reset();
    // push, not go: the sign in screen stays underneath. That matters on the
    // predictive back path (API 33+, default for targetSdk 36), where the
    // engine only forwards back to Dart while something in the tree reports it
    // can handle a pop (SystemNavigator.setFrameworkHandlesBack). On the
    // legacy onBackPressed path every press reaches popRoute, root route or
    // not, and go() reproduces it just as well. See README.md.
    router.push('/dashboard');
    setState(() => _hint = '');
  }

  /// Scenario 2 — how it shows up in production.
  ///
  /// A push notification / deep link handler navigating while the app is in
  /// the background. Arming this navigates the moment the app is paused, which
  /// is the point: no frames are produced while an app is in the background,
  /// so the shell cannot mount its Navigator until the app is resumed. The
  /// first back press after resume lands inside the window.
  void _armBackgroundNotification() {
    CrashReporter.clear();
    Session.instance.reset();
    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _lifecycle?.dispose();
        _lifecycle = null;
        router.push('/dashboard');
      },
    );
    setState(
      () => _hint =
          'Armed. Background the app, reopen it, and press the back button.',
    );
  }

  /// Scenario 3 — the minimal proof, no shell gating involved.
  ///
  /// `go()` updates `currentConfiguration` synchronously; the shell's
  /// Navigator only mounts on the next frame. This delivers the exact message
  /// the engine sends for the hardware back button inside that one-frame gap.
  void _syntheticRace() {
    CrashReporter.clear();
    Session.instance
      ..reset()
      ..slowShell = false;
    router.push('/dashboard');
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (ByteData? _) {},
    );
    setState(() => _hint = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acme')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton(
              key: const Key('sign-in'),
              onPressed: _signIn,
              child: const Text('Sign in'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            Text(
              'flutter/flutter#188993',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('slow-shell'),
              contentPadding: EdgeInsets.zero,
              value: Session.instance.slowShell,
              onChanged: (bool value) =>
                  setState(() => Session.instance.slowShell = value),
              title: const Text('Shell restores session first'),
              subtitle: const Text(
                'Keeps the shell navigator unmounted for 5s',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('push-notification'),
              onPressed: _armBackgroundNotification,
              child: const Text('Notification opens /dashboard in background'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('synthetic-race'),
              onPressed: _syntheticRace,
              child: const Text('Synthetic one-frame race'),
            ),
            if (_hint.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(_hint, key: const Key('hint')),
            ],
          ],
        ),
      ),
    );
  }
}
