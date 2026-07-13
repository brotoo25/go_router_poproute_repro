# go_router popRoute crash reproduction

Reproduces [flutter/flutter#188993](https://github.com/flutter/flutter/issues/188993):

```
TypeError: Null check operator used on a null value
  GoRouterDelegate._findCurrentNavigators (package:go_router/src/delegate.dart:126)
  GoRouterDelegate.popRoute (package:go_router/src/delegate.dart:58)
```

Fix proposed in [flutter/packages#12111](https://github.com/flutter/packages/pull/12111).

## What the transient state is

`go()` updates `GoRouterDelegate.currentConfiguration` synchronously (with
synchronous redirects the parser completes with a `SynchronousFuture`, so
`setNewRoutePath` runs inside the `go()` call), but the `Navigator` of a
`ShellRoute` in the new configuration only mounts when the next frame
builds. Until that frame, `currentConfiguration.matches.last` is already a
`ShellRouteMatch` while its `navigatorKey.currentState` is still null.

The Android back button arrives as a `popRoute` method call on the
`flutter/navigation` channel. Platform messages are not synchronized with
frames, so a back event can be processed inside that window, at which point
`_findCurrentNavigators` force-unwraps `walker.navigatorKey.currentState!`
and throws.

The window is normally a single frame, but it stretches in practice: no
frames are produced while an app is paused, so any navigation that happens
in the background (auth refresh listenable, push notification handler, deep
link, timer) leaves the new shell navigator unmounted until the first frame
after resume. A back press delivered right after the activity resumes lands
before that frame. Our production breadcrumbs show exactly that sequence
(paused, resumed, back press, crash), mostly on low-end devices where the
first frame after resume is slow.

## Running it

```
flutter pub get
flutter run                                 # tap one of the two buttons
flutter run --dart-define=AUTO_REPRO=true   # crashes by itself after ~2s
```

The app has two buttons:

1. "Reproduce (synthetic back event)": deterministic, works on any platform.
   Navigates onto the shell route, then delivers a `popRoute` message
   identical to the one the engine sends for the hardware back button,
   before the next frame. Only the timing is scripted here; the window
   itself comes from the framework's own ordering.
2. "Arm background navigation (real back button)": Android device or
   emulator, no synthetic events. Tap the button, background the app, wait
   3 seconds (the app navigates to the shell route while paused), reopen the
   app and immediately press the hardware back button.

## Expected output (go_router 17.3.0)

```
flutter: currentConfiguration.uri: /dashboard
flutter: currentConfiguration.matches.last is ShellRouteMatch: true
flutter: shell navigator mounted: false
flutter: delivering popRoute (hardware back) before the next frame...

══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════
The following _TypeError was thrown while dispatching notifications for
WidgetsBindingObserver.didPopRoute:
Null check operator used on a null value

#0      GoRouterDelegate._findCurrentNavigators (package:go_router/src/delegate.dart:126:43)
#1      GoRouterDelegate.popRoute (package:go_router/src/delegate.dart:58:45)
#2      _RouterState._handleBackButtonDispatcherNotification (package:flutter/src/widgets/router.dart:807:34)
#3      _CallbackHookProvider.invokeCallback (package:flutter/src/widgets/router.dart:934:31)
#4      BackButtonDispatcher.invokeCallback (package:flutter/src/widgets/router.dart:1017:18)
#5      RootBackButtonDispatcher.didPopRoute (package:flutter/src/widgets/router.dart:1112:33)
#6      WidgetsBinding.handlePopRoute (package:flutter/src/widgets/binding.dart:1116:28)
<asynchronous suspension>
#7      MethodChannel._handleAsMethodCall (package:flutter/src/services/platform_channel.dart:607:42)
<asynchronous suspension>
#8      _DefaultBinaryMessenger.setMessageHandler.<anonymous closure> (package:flutter/src/services/binding.dart:663:22)
<asynchronous suspension>
```

The stack matches the production crash reports in the issue, including line
numbers.

## Verifying the fix

Uncomment the `dependency_overrides` block in `pubspec.yaml` (it points at
the branch from flutter/packages#12111), run `flutter pub get` and repeat
the same steps. No exception is thrown: `popRoute()` returns false and the
system back proceeds, so the app moves to the background, which is what a
user at the root of a shell would expect from the back button.
