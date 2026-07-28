import 'dart:async';

import 'package:flutter/foundation.dart';

/// Stands in for the async work a real app does before its shell can render:
/// refreshing an auth token, opening a local database, fetching remote config.
///
/// This is the realistic source of the crash window. While [isReady] is false
/// the shell renders a loading screen *instead of* the `Navigator` that
/// go_router handed it, so `ShellRouteMatch.navigatorKey.currentState` stays
/// null even though `currentConfiguration.matches.last` is already that
/// `ShellRouteMatch`.
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  /// When false the shell mounts go_router's `Navigator` on its very first
  /// build, which reduces the window back to the single frame described in
  /// flutter/flutter#188993.
  bool slowShell = true;

  /// Long enough for a person (or an automation tool) to press the hardware
  /// back button while the shell is still restoring.
  Duration restoreDelay = const Duration(seconds: 5);

  bool _ready = false;
  bool get isReady => _ready;

  Timer? _timer;

  /// Called from the shell's `initState`, i.e. the first frame on which the
  /// shell route is in the configuration.
  void beginRestore() {
    _timer?.cancel();
    if (!slowShell) {
      _ready = true;
      return;
    }
    _ready = false;
    _timer = Timer(restoreDelay, () {
      _ready = true;
      notifyListeners();
    });
  }

  /// Back to signed-out, so a flow can run more than one scenario.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _ready = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
