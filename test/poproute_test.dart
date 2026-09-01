// On go_router 17.3.0 the first two tests fail with
// `Null check operator used on a null value` thrown by
// GoRouterDelegate._findCurrentNavigators (delegate.dart:126).
// With flutter/packages#12111 all three pass.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:go_router_poproute_repro/main.dart';

void main() {
  setUp(() => router.go('/'));

  Future<void> signIn(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Sign in'));
  }

  void expectShellInConfigurationButNotMounted() {
    expect(
      router.routerDelegate.currentConfiguration.matches.last,
      isA<ShellRouteMatch>(),
    );
    expect(shellNavigatorKey.currentState, isNull);
  }

  testWidgets('back while the shell shows its loading screen', (tester) async {
    await signIn(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Restoring session'), findsOneWidget);
    expectShellInConfigurationButNotMounted();

    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('back in the frame between push() and the shell being built', (
    tester,
  ) async {
    await signIn(tester);
    expectShellInConfigurationButNotMounted();

    // The tree still shows the sign in screen, so there is nothing to pop yet.
    expect(await router.routerDelegate.popRoute(), isFalse);
  });

  testWidgets('back once the shell has mounted', (tester) async {
    await signIn(tester);
    await tester.pumpAndSettle();
    await tester.pump(sessionRestoreDelay);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(shellNavigatorKey.currentState, isNotNull);

    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });
}
