import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router_poproute_repro/src/crash_reporter.dart';

/// Delivers the exact platform message the Android engine sends when the user
/// presses the hardware back button.
///
/// This is the same `flutter/navigation` `popRoute` call that
/// `FlutterActivityAndFragmentDelegate` produces, so everything below it
/// (`WidgetsBinding.handlePopRoute` -> `RootBackButtonDispatcher.didPopRoute`
/// -> `GoRouterDelegate.popRoute`) runs unchanged. The returned future
/// completes once the framework has finished handling it, including reporting
/// any exception.
Future<void> pressSystemBackButton() {
  final Completer<void> handled = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (ByteData? _) => handled.complete(),
  );
  return handled.future;
}

/// Intercepts `SystemNavigator.pop`.
///
/// `WidgetsBinding.handlePopRoute` calls it when no observer handled the pop,
/// including when an observer threw. On a real device that closes the app,
/// which would take the test process with it, so it is recorded instead.
/// The returned list is also the assertion: a non-empty list means the back
/// press closed the app rather than navigating.
List<String> recordSystemNavigatorPops(WidgetTester tester) {
  final List<String> pops = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'SystemNavigator.pop') {
        pops.add(call.method);
      }
      return null;
    },
  );
  return pops;
}

/// Redirects framework errors into the returned list instead of failing the
/// test, so a test can assert on the crash. Also keeps [CrashReporter] fed,
/// which is what draws the banner the Maestro flows assert on.
List<FlutterErrorDetails> collectFrameworkErrors() {
  final List<FlutterErrorDetails> collected = <FlutterErrorDetails>[];
  FlutterError.onError = (FlutterErrorDetails details) {
    collected.add(details);
    CrashReporter.record(details);
  };
  return collected;
}

/// True when [details] is the crash from flutter/flutter#188993.
bool isPopRouteCrash(FlutterErrorDetails details) =>
    details.exception is TypeError &&
    details.exception.toString().contains('Null check operator') &&
    details.stack.toString().contains(
      'GoRouterDelegate._findCurrentNavigators',
    );
