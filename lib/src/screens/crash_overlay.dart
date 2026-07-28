import 'package:flutter/material.dart';

import '../crash_reporter.dart';

/// Renders whatever [CrashReporter] captured, from this run or the previous
/// one.
///
/// The framework swallows the exception from flutter/flutter#188993 and closes
/// the app, so for the back button scenarios the only banner a driver can ever
/// see is the "previous run" one on the next launch.
class CrashOverlay extends StatelessWidget {
  const CrashOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CapturedCrash?>(
      valueListenable: CrashReporter.last,
      builder: (BuildContext context, CapturedCrash? live, _) {
        return ValueListenableBuilder<CapturedCrash?>(
          valueListenable: CrashReporter.previousRun,
          builder: (BuildContext context, CapturedCrash? previous, _) {
            final CapturedCrash? crash = live ?? previous;
            if (crash == null) {
              return const SizedBox.shrink();
            }
            return _CrashBanner(
              title: live != null ? 'CRASH CAPTURED' : 'PREVIOUS RUN CRASHED',
              crash: crash,
            );
          },
        );
      },
    );
  }
}

class _CrashBanner extends StatelessWidget {
  const _CrashBanner({required this.title, required this.crash});

  final String title;
  final CapturedCrash crash;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Material(
          key: const Key('crash-banner'),
          color: const Color(0xFFB3261E),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Each line gets its own semantics node. Without `container`
                // they are merged into one accessibility label, and a driver
                // that matches on the full string (Maestro does) cannot assert
                // on any single line.
                _Line(
                  text: title,
                  semanticsKey: const Key('crash-title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                _Line(
                  text: crash.exception,
                  semanticsKey: const Key('crash-exception'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 4),
                _Line(
                  text: crash.symbol,
                  semanticsKey: const Key('crash-symbol'),
                  style: const TextStyle(color: Colors.white70),
                ),
                _Line(
                  text: crash.location,
                  semanticsKey: const Key('crash-location'),
                  style: const TextStyle(color: Colors.white70),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('crash-dismiss'),
                    onPressed: CrashReporter.clear,
                    child: const Text(
                      'Dismiss',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the report, exposed as its own accessibility node.
class _Line extends StatelessWidget {
  const _Line({
    required this.text,
    required this.semanticsKey,
    required this.style,
  });

  final String text;
  final Key semanticsKey;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: semanticsKey,
      container: true,
      label: text,
      excludeSemantics: true,
      child: Text(text, style: style),
    );
  }
}
