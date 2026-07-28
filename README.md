# go_router popRoute crash reproduction

Reproduces [flutter/flutter#188993](https://github.com/flutter/flutter/issues/188993):

```
TypeError: Null check operator used on a null value
  GoRouterDelegate._findCurrentNavigators (package:go_router/src/delegate.dart:126)
  GoRouterDelegate.popRoute (package:go_router/src/delegate.dart:58)
```

Fix proposed in [flutter/packages#12111](https://github.com/flutter/packages/pull/12111).

This is a small but realistic app (sign in, a shell with a bottom bar), driven
by **real user interactions**: Maestro taps the buttons and presses the
device's own back key, and the crash it produces is the one in the issue.

## The defect

`GoRouterDelegate._findCurrentNavigators` walks the shell matches of the
current configuration and force-unwraps each one's navigator:

```dart
RouteMatchBase walker = currentConfiguration.matches.last;
while (walker is ShellRouteMatch) {
  final NavigatorState potentialCandidate = walker.navigatorKey.currentState!; // delegate.dart:126
```

`canPop()` twenty lines above uses `?.` for the same lookup. `popRoute` does
not, so **any** moment in which the configuration already contains a
`ShellRouteMatch` whose `Navigator` is not in the tree turns a back press into
a `TypeError`.

### That window is not always one frame

The issue describes the frame-sized race: `go()`/`push()` update
`currentConfiguration` synchronously, but the shell's `Navigator` only mounts
when the next frame builds.

It is much wider than that whenever a shell renders something other than the
`child` go_router handed it, which is an ordinary thing for a shell to do:

```dart
ShellRoute(
  navigatorKey: shellNavigatorKey,
  builder: (_, _, Widget child) => AppShell(child: child),
  ...
)

// AppShell.build
if (!Session.instance.isReady) {
  return const _RestoringSessionScreen(); // `child` is NOT in the tree
}
return Scaffold(body: widget.child, bottomNavigationBar: ...);
```

Restoring a session, opening a database, fetching remote config, waiting on a
connectivity check: for as long as the shell shows a loading screen,
`currentConfiguration.matches.last` is the `ShellRouteMatch` and
`shellNavigatorKey.currentState` is `null`. Every back press in that period
crashes. That is what makes this reproducible with a real finger on a real
back button instead of a 16ms race, and it is why the production reports
cluster on slow devices and after resume.

### Two things worth knowing when reproducing it

**The back press only reaches Dart if something is poppable.** Flutter tells
the platform whether it will handle back via
`SystemNavigator.setFrameworkHandlesBack`. With a single root page, Android
consumes the back press itself and go_router never sees it. So this app uses
`push('/dashboard')`, not `go`, leaving the sign in screen underneath. Any real
app that is more than one screen deep satisfies this.

**The user-visible symptom is the app closing.**
`WidgetsBinding.handlePopRoute` catches whatever `didPopRoute` throws, reports
it, and then carries on to the fallback:

```dart
try {
  if (await observer.didPopRoute()) return true;
} catch (exception, stack) {
  FlutterError.reportError(...);   // swallowed
}
...
SystemNavigator.pop();             // app closes
```

So the exception never reaches the user as a crash dialog. The back button
just quits the app. The activity dies with it, which is why this app writes
the captured error to disk and shows it on the next launch, the same way a
crash reporter does.

## Running it

Two drivers, both against the same app and both verified green. An Android
device or emulator is required for the real back key.

### Maestro (real taps, real hardware back button)

```
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
maestro test maestro/flows/
```

```
[Passed] Notification navigates while the app is backgrounded (13s)
[Passed] Back button during session restore (11s)
[Passed] One frame race between push() and the shell Navigator (8s)
[Passed] Back button after the shell has mounted (11s)

4/4 Flows Passed in 43s
```

Nothing in `01` and `02` is synthetic: Maestro taps what a user taps and sends
`KEYCODE_BACK`. `03` is the control, and is the reason the others are
convincing: the same key press, after the shell has mounted, correctly returns
to the sign in screen and reports no crash.

`flutter test integration_test/...` overwrites the installed APK with one whose
entry point is the test file, so rebuild and reinstall before running the flows
again if you have run the integration tests in between.

### integration_test (real gestures, deterministic)

```
flutter test integration_test/poproute_crash_test.dart -d <device>
```

Taps drive every navigation. The back press is the exact `flutter/navigation`
`popRoute` message the engine sends, pushed through `channelBuffers`, so
`handlePopRoute` -> `RootBackButtonDispatcher` -> `GoRouterDelegate.popRoute`
runs unchanged. `SystemNavigator.pop` is intercepted so the test can assert on
it instead of being killed by it.

Two tests: the crash during session restore, and the same back press after the
shell has mounted, which must not crash. Scenario 2 is not here on purpose. Its
premise is that a paused app produces no frames, and a live test binding keeps
driving frames and reasserting `resumed`, so simulating it would prove nothing.
The Maestro flow runs it for real instead.

### Why there is no Patrol (or any in-Dart) test of the native back key

Worth knowing before you try: **no in-process Dart test can assert on what
happens after a real back press that lands in the crash window.** A real back
press finishes the activity, because Android's predictive back commits the
gesture, `_handleCommitBackGesture` throws, and the activity goes away. That
takes the Dart isolate running the test with it, so the run stops at the key
press with no assertion executed and no failure reported.

Mocking `SystemNavigator.pop`, which is what lets the integration_test above
assert on the fallthrough, does not help: here it is Android that finishes the
activity, not Dart.

That is why Maestro is the driver that proves the real key event. It asserts
from outside the process, so it survives the app being closed, and the closing
is itself one of the things it asserts.

## The three scenarios in the app

1. **Sign in** — `push`es onto the shell route while it restores the session.
   Back during the 5 second loading screen crashes. Realistic and wide enough
   to hit by hand.
2. **Notification opens /dashboard in background** — arms a handler that
   navigates the moment the app is paused. A backgrounded app produces no
   frames, so the shell cannot mount its `Navigator` until the app is resumed,
   and the first back press after resume lands in the window. This is the
   sequence in the production breadcrumbs: paused, navigate, resumed, back,
   crash.
3. **Synthetic one-frame race** — turns the session gate off and pushes the
   engine's own `popRoute` message inside the single frame between `push()` and
   the shell mounting. Only the timing is scripted; the ordering is the
   framework's. This is the minimal form of the bug from the issue.

The switch on the home screen toggles the session gate for scenarios 1 and 2.

## Observed output (go_router 17.3.0, Flutter 3.44.6, Android 16)

Real hardware back button, during the session restore:

```
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════
The following _TypeError was thrown while dispatching notifications for
WidgetsBindingObserver.didPopRoute:
Null check operator used on a null value

When the exception was thrown, this was the stack:
#0      GoRouterDelegate._findCurrentNavigators (package:go_router/src/delegate.dart:126:43)
#1      GoRouterDelegate.popRoute (package:go_router/src/delegate.dart:58:45)
#2      _RouterState._handleBackButtonDispatcherNotification (package:flutter/src/widgets/router.dart:807:34)
#3      _CallbackHookProvider.invokeCallback (package:flutter/src/widgets/router.dart:934:31)
#4      BackButtonDispatcher.invokeCallback (package:flutter/src/widgets/router.dart:1017:18)
#5      RootBackButtonDispatcher.didPopRoute (package:flutter/src/widgets/router.dart:1112:33)
#6      WidgetsBinding.handlePopRoute (package:flutter/src/widgets/binding.dart:1116:28)
<asynchronous suspension>
#7      WidgetsBinding._handleCommitBackGesture (package:flutter/src/widgets/binding.dart:1203:7)
<asynchronous suspension>
#8      MethodChannel._handleAsMethodCall (package:flutter/src/services/platform_channel.dart:607:42)
<asynchronous suspension>
#9      _DefaultBinaryMessenger.setMessageHandler.<anonymous closure> (package:flutter/src/services/binding.dart:663:22)
<asynchronous suspension>
```

`#7` is Android's predictive back; on the synthetic path frame `#7` is
`MethodChannel._handleAsMethodCall` directly, which is the stack quoted in the
issue. Frames `#0` to `#6` are identical either way, including line numbers.

## Verifying the fix

Uncomment the `dependency_overrides` block in `pubspec.yaml` (it points at the
branch from flutter/packages#12111), then:

```
flutter pub get
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
maestro test maestro/flows/03_control_shell_mounted.yaml
```

With the fix, `popRoute()` returns false instead of throwing, the system back
proceeds, and the app is backgrounded rather than crashed. Flows `01`, `02` and
`04` assert the crash and are expected to fail against the fixed version; `03`
is expected to pass against both.

## Notes

- The crash reporter (`lib/src/crash_reporter.dart`) and the banner exist only
  so a black box driver can see which exception closed the app. They are not
  part of the reproduction.
- If `maestro test` fails with `io.grpc.StatusRuntimeException: UNAVAILABLE`,
  its on-device driver is not running. `maestro test` normally installs it; if
  a stale entry in `~/.maestro/sessions` makes it skip that step, clear the
  file and retry.
