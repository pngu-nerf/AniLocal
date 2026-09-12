import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the live harnesses look for the reference library. Defaults to the
/// maintainer's mount; another machine points `ANILOCAL_LIVE_ROOT` at its own
/// copy instead of editing the harness.
String get liveLibraryRoot =>
    Platform.environment['ANILOCAL_LIVE_ROOT'] ?? '/Volumes/Anime';

/// Whether [tool] is on PATH. The harnesses lean on `ffprobe` (the independent
/// authority for chapter marks) and the `sqlite3` CLI (to snapshot the live
/// cache without adding a dependency); a machine without them should SKIP,
/// not fail with an opaque `ProcessException`.
bool hasTool(String tool) => Process.runSync('which', [tool]).exitCode == 0;

/// Skips the current test — with the reason on record — when the library is
/// not mounted or a tool this harness needs is missing. Returns true when the
/// test may proceed. A skip is the honest answer here: a live harness whose
/// result depends on what is plugged in stops meaning anything if a missing
/// drive reads as a red suite.
bool liveReady({List<String> tools = const []}) {
  if (!Directory(liveLibraryRoot).existsSync()) {
    markTestSkipped(
      '$liveLibraryRoot is not mounted (set ANILOCAL_LIVE_ROOT to override)',
    );
    return false;
  }
  for (final t in tools) {
    if (!hasTool(t)) {
      markTestSkipped('$t is not on PATH — this harness needs it');
      return false;
    }
  }
  return true;
}
