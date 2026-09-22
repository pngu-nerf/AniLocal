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
      } catch (e) {
        // `catch` everything, Errors included: this is the button you press
        // when the app is already broken, so it must not be the thing that
        // fails next.
        head.writeln('(report builder failed: $e)');
      }
      head.writeln();
    }
    head
      ..writeln('--- recent log ---')
      ..write(AppLog.dump());
    return redactHome(head.toString());
  }

  /// Replace the user's home directory with `~` wherever it appears.
  ///
  /// The log names library folders and the log file itself, which puts the
  /// macOS username in every path; a report is written to be pasted into a
  /// public issue, so the one identifier we can strip, we strip. Folder names
  /// under it stay — they are what the report is about.
  static String redactHome(String text, {Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    // HOME on macOS/Linux; USERPROFILE is Windows' name for the same thing.
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null || home.isEmpty) return text;
    return text.replaceAll(home, '~');
  }

  /// Reveal the log file in the platform's file browser: Finder (selected),
  /// Explorer (selected), or the folder in whatever handles `xdg-open`. An
  /// unknown platform is a no-op rather than an error.
  static Future<void> revealLogFolder() async {
    final path = AppLog.filePath;
    if (path == null) return;
    final (String, List<String>)? command = switch (Platform.operatingSystem) {
      'macos' => ('open', ['-R', path]),
      'windows' => ('explorer.exe', ['/select,', path]),
      'linux' => ('xdg-open', [File(path).parent.path]),
      _ => null,
    };
    if (command == null) return;
    try {
      await Process.run(command.$1, command.$2);
    } on ProcessException catch (e) {
      AppLog.warn('Could not reveal log folder', error: e);
    }
  }
}
