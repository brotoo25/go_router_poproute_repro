# go_router popRoute crash reproduction

Reproduces [flutter/flutter#188993](https://github.com/flutter/flutter/issues/188993),
fixed by [flutter/packages#12111](https://github.com/flutter/packages/pull/12111).

```
Null check operator used on a null value
#0 GoRouterDelegate._findCurrentNavigators (package:go_router/src/delegate.dart:126:43)
#1 GoRouterDelegate.popRoute (package:go_router/src/delegate.dart:58:45)
```

## The transient state

`popRoute` walks the shell matches in `currentConfiguration` and force-unwraps
each shell's navigator:

```dart
RouteMatchBase walker = currentConfiguration.matches.last;
while (walker is ShellRouteMatch) {
  final NavigatorState potentialCandidate = walker.navigatorKey.currentState!;
```

`currentConfiguration` is updated inside `push()` and `go()`. The `Navigator`
behind a `ShellRouteMatch` only exists once the shell's `builder` has put
`child` in the tree, which happens on a later frame at the earliest. Any back
press in between throws:

- in the frame between the navigation and the next build, the window the
  issue describes;
- for as long as the app is paused, when something navigates in the
  background, since a paused app builds no frames. This is the pause, resume,
  back sequence in the issue's production breadcrumbs, and is not driven by
  this app;
- for as long as the shell renders something other than `child`. This app's
  `AppShell` shows "Restoring session" for 5 seconds before it renders the
  `Navigator`, the ordinary shape of a shell that refreshes a token or opens a
  database first. That window is wide enough to hit by hand.

`canPop()`, in the same file, does the same lookup with `?.` and is fine.

The user never sees the exception. `WidgetsBinding.handlePopRoute` catches
what `didPopRoute` throws, reports it, and falls through to
`SystemNavigator.pop()`, so the back button closes the app.

## Run it

```
flutter test
```

No device needed. The first two tests sign in with a tap, check that
`currentConfiguration.matches.last` is the `ShellRouteMatch` while
`shellNavigatorKey.currentState` is null, and press back. The third waits for
the shell to mount before pressing back.

The tests assert the correct behaviour, so which ones pass depends on the
go_router version in `pubspec.yaml`:

| test | go_router 17.3.0 | flutter/packages#12111 |
|---|---|---|
| back while the shell shows its loading screen | fails, stack above | passes |
| back in the frame between push() and the shell being built | fails, stack above | passes |
| back once the shell has mounted | passes | passes |

To switch between the two, uncomment the `dependency_overrides` block in
`pubspec.yaml` to use the fix, or comment it out again to go back to 17.3.0,
then run:

```
flutter pub get
flutter test
```

On 17.3.0 the run ends with:

```
00:00 +0 -1: back while the shell shows its loading screen [E]
00:00 +0 -2: back in the frame between push() and the shell being built [E]
00:00 +1 -2: Some tests failed.
```

With the fix:

```
00:00 +3: All tests passed!
```

```
flutter run -d <android device>
```

Tap "Sign in", then press the back button while "Restoring session" is on
screen. The app closes and the stack is in the console.

The app uses `push` rather than `go` so the sign in screen stays underneath.
With predictive back, on by default for apps targeting Android 16, the engine
only forwards the back button to Dart while the framework reports it can pop.
On the legacy `onBackPressed` path, which is where the production reports come
from, every press reaches `popRoute`, so `go` crashes as well, root route or
not.

## What the right behaviour is

The review asks whether popping the parent navigator is right, or whether the
configuration should never be allowed into this state.

go_router cannot keep it out. `currentConfiguration` is the input to the next
build; the shell's `Navigator` is an output of it, and whether the build
produces one is decided by the shell's `builder`, which is application code.
Even a builder that always returns `child` has the one-frame gap, and has it
for the whole time the app is paused. Refusing the state means refusing to
navigate.

The fix stops walking at the first unmounted shell, which is what `canPop()`
already does. An unmounted navigator has nothing to pop, so skipping it does
not change what gets popped. The third test is the control: with the shell
mounted, its navigator holds a single page, the pop bubbles to the root, and
the app is back on the sign in screen. With the fix, the first test ends in
the same place. In the second test the tree has not been rebuilt at all yet,
so the root navigator still holds only the sign in page and the press is
handled as it would have been one frame earlier: nothing to pop, `popRoute`
returns `false`, and the platform backgrounds the app.

Reporting the press as handled instead (`return true`) would be worse: on a
root route the app would neither pop nor background, and back would look
dead.
