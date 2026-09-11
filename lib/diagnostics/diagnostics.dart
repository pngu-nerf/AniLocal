import 'dart:io';

import 'app_log.dart';

/// What the About panel and the error screens show and copy.
///
/// A static surface, like [AppLog] and `WindowChrome`, for the same reason: it
/// must be reachable from any screen without threading five more constructor
/// parameters through the widget tree for something that is neither state nor
/// a repository. The composition root fills it in once at startup; the UI
/// only reads.
abstract final class Diagnostics {
  /// `version+build` from the bundle, or 'unknown' before startup sets it.
  static String appVersion = 'unknown';

  /// Builds the full report: version, schema, counts, active settings, then
  /// the log ring. Installed by main(), which is the only place that can see
  /// the database and the repositories. Null = report is the log alone.
  static Future<String> Function()? reportBuilder;

  /// Everything a bug report needs, as one string for the clipboard.
  static Future<String> report() async {
    final head = StringBuffer()
      ..writeln('AniLocal $appVersion')
      ..writeln(
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('log file: ${AppLog.filePath ?? '(not attached)'}')
      ..writeln();
    final body = reportBuilder;
    if (body != null) {
      try {
        head.writeln(await body());
      } on Exception catch (e) {
        head.writeln('(report builder failed: $e)');
      }
      head.writeln();
    }
    head
      ..writeln('--- recent log ---')
      ..write(AppLog.dump());
    return head.toString();
  }

  /// Reveal the log folder in Finder. macOS only by construction (`open`);
  /// elsewhere this is a no-op rather than an error.
  static Future<void> revealLogFolder() async {
    final path = AppLog.filePath;
    if (path == null || !Platform.isMacOS) return;
    try {
      await Process.run('open', ['-R', path]);
    } on ProcessException catch (e) {
      AppLog.warn('Could not reveal log folder', error: e);
    }
  }
}
