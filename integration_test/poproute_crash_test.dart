// On-device reproduction driven by real widget interactions.
//
// Every navigation here is caused by a tap, and the back press is the exact
// `flutter/navigation` `popRoute` message the engine sends for the hardware
// back button. Nothing about go_router's ordering is faked.
//
//   flutter test integration_test/poproute_crash_test.dart -d emulator-5554
//
// For the genuinely native back key, see maestro/flows.
//
// The "navigate while backgrounded" scenario is deliberately not here. Its
// premise is that a paused app produces no frames, and a live test binding
// keeps driving frames and reasserting `resumed`, so simulating it would prove
// nothing. maestro/flows/02_notification_while_backgrounded.yaml runs it for
// real with the device's Home and Back keys.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_router_poproute_repro/main.dart' as app;
import 'package:go_router_poproute_repro/src/crash_reporter.dart';
import 'package:go_router_poproute_repro/src/router.dart';
import 'package:go_router_poproute_repro/src/session.dart';

import 'support/back_button.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    CrashReporter.install();
    await CrashReporter.loadPreviousRun();
  });

  /// Boots the app and takes over error reporting and SystemNavigator.pop.
  ///
  /// The router, the session and the reporter are process globals that outlive
  /// a single test, so they are reset before the tree is built. Note the
  /// absence of pumpAndSettle: these tests deliberately leave the app on a
  /// loading screen whose spinner never settles.
  Future<(List<FlutterErrorDetails>, List<String>)> launchApp(
    WidgetTester tester,
  ) async {
    router.go('/');
    Session.instance.reset();
    CrashReporter.clear();
    await tester.pumpWidget(const app.ReproApp());
    await tester.pump();
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
    return (collectFrameworkErrors(), recordSystemNavigatorPops(tester));
  }

  /// Taps "Sign in" and lets the shell route build. The loading spinner never
  /// settles, so frames are pumped explicitly rather than with pumpAndSettle.
  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pump();
    await tester.pump();
  }

  /// Bounded stand-in for pumpAndSettle, which cannot be used here.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('flutter/flutter#188993', () {
    testWidgets('back press while the shell restores the session crashes', (
      WidgetTester tester,
    ) async {
      final (errors, pops) = await launchApp(tester);
      Session.instance.slowShell = true;

      await signIn(tester);

      // The user sees a loading screen. go_router already considers itself to
      // be on the shell route, but the shell has not put go_router's Navigator
      // in the tree yet.
      expect(find.byKey(const Key('restoring-session')), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.matches.last,
        isA<ShellRouteMatch>(),
        reason: 'the shell match is already the active configuration',
      );
      expect(
        shellNavigatorKey.currentState,
        isNull,
        reason: 'but its Navigator is not mounted, so currentState is null',
      );

      await pressSystemBackButton();
      await tester.pump();

      expect(
        errors.where(isPopRouteCrash),
        isNotEmpty,
        reason: 'the back button should have thrown inside go_router',
      );
      expect(
        errors.first.stack.toString(),
        contains('package:go_router/src/delegate.dart'),
      );

      // The symptom: handlePopRoute swallowed the TypeError and fell through
      // to SystemNavigator.pop(), so the back press closes the app instead of
      // navigating.
      expect(
        pops,
        isNotEmpty,
        reason: 'the failed pop fell through to SystemNavigator.pop()',
      );

      // What the app's error reporter recorded, and what the Maestro flows
      // assert on after relaunching.
      await tester.pump();
      expect(CrashReporter.last.value?.isTargetCrash, isTrue);
      expect(
        CrashReporter.last.value?.symbol,
        'GoRouterDelegate._findCurrentNavigators',
      );
      expect(
        CrashReporter.last.value?.location,
        startsWith('package:go_router/src/delegate.dart:126'),
      );
    });

    testWidgets('the same back press is harmless once the shell has mounted', (
      WidgetTester tester,
    ) async {
      final (errors, pops) = await launchApp(tester);
      Session.instance.slowShell = true;

      await signIn(tester);
      expect(find.byKey(const Key('restoring-session')), findsOneWidget);

      // Wait out the session restore: the shell now mounts go_router's
      // Navigator.
      await tester.pump(Session.instance.restoreDelay);
      await tester.pump();
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
      expect(shellNavigatorKey.currentState, isNotNull);

      await pressSystemBackButton();
      await settle(tester);

      expect(
        errors,
        isEmpty,
        reason: 'only the unmounted shell navigator causes the crash',
      );
      expect(
        pops,
        isEmpty,
        reason: 'the pop was handled, so the app is not closed',
      );
      expect(find.byKey(const Key('sign-in')), findsOneWidget);
    });

  });
}
