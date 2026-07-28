import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A framework error captured by [CrashReporter].
@immutable
class CapturedCrash {
  const CapturedCrash({
    required this.exception,
    required this.symbol,
    required this.location,
  });

  factory CapturedCrash.fromJson(Map<String, dynamic> json) => CapturedCrash(
    exception: json['exception'] as String? ?? '',
    symbol: json['symbol'] as String? ?? '',
    location: json['location'] as String? ?? '',
  );

  /// e.g. `Null check operator used on a null value`.
  final String exception;

  /// e.g. `GoRouterDelegate._findCurrentNavigators`.
  final String symbol;

  /// e.g. `package:go_router/src/delegate.dart:126:43`.
  final String location;

  /// True when this is the crash from flutter/flutter#188993 rather than some
  /// unrelated framework error.
  bool get isTargetCrash =>
      exception.contains('Null check operator') &&
      symbol.contains('_findCurrentNavigators');

  Map<String, dynamic> toJson() => <String, dynamic>{
    'exception': exception,
    'symbol': symbol,
    'location': location,
  };
}

/// Stands in for the error reporter a production app installs (Crashlytics,
/// Sentry, ...).
///
/// `WidgetsBinding.handlePopRoute` catches whatever `didPopRoute` throws,
/// reports it, and then falls through to `SystemNavigator.pop()`. So the back
/// press that triggers flutter/flutter#188993 closes the activity, and any
/// evidence held in memory dies with it.
///
/// That is why the crash is written to disk the moment it is reported and
/// surfaced on the next launch: it is the only way a black box driver
/// (Maestro) can see which exception closed the app, and it is exactly what a
/// real crash reporter does.
abstract final class CrashReporter {
  /// A crash captured during this run.
  static final ValueNotifier<CapturedCrash?> last =
      ValueNotifier<CapturedCrash?>(null);

  /// A crash left behind by the previous run.
  static final ValueNotifier<CapturedCrash?> previousRun =
      ValueNotifier<CapturedCrash?>(null);

  static FlutterExceptionHandler? _previous;
  static File? _store;

  /// Chains onto whatever handler is already installed, so the normal red
  /// console output is preserved.
  static void install() {
    _previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      record(details);
      _previous?.call(details);
    };
  }

  /// Picks up anything the previous run wrote before it was closed.
  static Future<void> loadPreviousRun() async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final File store = File('${dir.path}/last_crash.json');
      _store = store;
      if (store.existsSync()) {
        previousRun.value = CapturedCrash.fromJson(
          jsonDecode(store.readAsStringSync()) as Map<String, dynamic>,
        );
        store.deleteSync();
      }
    } on Object {
      // A repro app has nothing useful to do if its own reporter fails.
    }
  }

  /// Matches `#0      Symbol.name (package:go_router/src/delegate.dart:126:43)`.
  static final RegExp _goRouterFrame = RegExp(
    r'#\d+\s+(\S+)\s+\((package:go_router/[^)]+)\)',
  );

  static void record(FlutterErrorDetails details) {
    final Match? frame = _goRouterFrame.firstMatch(details.stack.toString());
    final CapturedCrash crash = CapturedCrash(
      exception: details.exception.toString(),
      symbol: frame?.group(1) ?? '<no go_router frame>',
      location: frame?.group(2) ?? '<unknown>',
    );
    // Synchronous on purpose: SystemNavigator.pop() is only a few statements
    // away, and the activity does not survive it.
    try {
      _store?.writeAsStringSync(jsonEncode(crash.toJson()));
    } on Object {
      // ignore
    }
    // reportError can fire mid-build; defer so listeners rebuild safely.
    scheduleMicrotask(() => last.value = crash);
  }

  static void clear() {
    last.value = null;
    previousRun.value = null;
    try {
      if (_store?.existsSync() ?? false) {
        _store!.deleteSync();
      }
    } on Object {
      // ignore
    }
  }
}
