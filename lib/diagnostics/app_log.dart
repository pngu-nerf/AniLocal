import 'dart:developer' as developer;
import 'dart:io';

/// Severity of a log line. Three is enough: what happened, what degraded, what
/// broke.
enum LogLevel { info, warn, error }

/// The ONE place the app records that something happened.
///
/// Before this there was nothing — no `print`, no logger, no error hook. Every
/// failure in the fill path resolved to a snackbar count or a swallowed null,
/// so "my library disappeared" and "skips are wrong" had no evidence trail at
/// all. This is deliberately small: a bounded in-memory ring (what the
/// "Copy diagnostics" button hands you) plus an append-only file under the app
/// support directory that rotates at ~1MB with one backup.
///
/// It NEVER throws. A logger that can crash the thing it is observing is worse
/// than none; a failed file write is dropped and the ring keeps going. It is
/// static because it has to be reachable from every layer without threading a
/// dependency through twenty constructors — the same reason `WindowChrome` is.
/// It lives in its own top-level folder (like `lib/playback`) so the UI can
/// import it without touching `lib/data`, keeping seam #1 intact.
abstract final class AppLog {
  /// How many recent lines are kept in memory for diagnostics.
  static const int ringCapacity = 500;

  /// File rotates past this: `app.log` -> `app.log.1`, the previous `.1` gone.
  static const int maxFileBytes = 1 << 20;

  static final List<String> _ring = <String>[];
  static File? _file;
  static int _fileBytes = 0;
  static bool _debug = false;

  /// Where the current log file is, or null when only the ring is active.
  static String? get filePath => _file?.path;

  /// The most recent lines, oldest first. Never more than [ringCapacity].
  static List<String> recent() => List.unmodifiable(_ring);

  /// Point the file sink at [directory]. Optional: without it, only the ring
  /// is kept — which is what tests and the very first milliseconds of startup
  /// get. Rotates on open if the existing file is already over the cap.
  static Future<void> attachFile(
    Future<Directory> Function() directory, {
    bool debugEcho = false,
  }) async {
    _debug = debugEcho;
    try {
      final dir = await directory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/app.log');
      if (await file.exists()) {
        _fileBytes = await file.length();
        if (_fileBytes > maxFileBytes) {
          await _rotate(file);
        }
      } else {
        _fileBytes = 0;
      }
      _file = file;
      // Anything logged before the file was attached is carried across.
      for (final line in _ring) {
        _append(line);
      }
    } on Exception {
      _file = null; // ring-only; a logger must never take the app down
    }
  }

  static void info(String message) => _write(LogLevel.info, message);

  static void warn(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.warn, message, error: error, stack: stack);

  static void error(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.error, message, error: error, stack: stack);

  /// Everything the ring holds, joined — what "Copy diagnostics" pastes.
  static String dump() => _ring.join('\n');

  /// Forget everything. Tests only; production never resets.
  static void reset() {
    _ring.clear();
    _file = null;
    _fileBytes = 0;
  }

  static void _write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' ')
      ..write(level.name.toUpperCase().padRight(5))
      ..write(' ')
      ..write(message);
    if (error != null) buffer.write(' — $error');
    if (stack != null) buffer.write('\n$stack');
    final line = buffer.toString();
    _ring.add(line);
    if (_ring.length > ringCapacity) _ring.removeAt(0);
    if (_debug) {
      developer.log(message, name: 'anilocal', level: _developerLevel(level));
    }
    if (_file != null) _append(line);
  }

  static void _append(String line) {
    final file = _file;
    if (file == null) return;
    try {
      // Synchronous on purpose: a log line that races the crash it describes
      // is a log line that never lands. These are short writes to a local
      // file; the cost is invisible next to a single network request.
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
      _fileBytes += line.length + 1;
      if (_fileBytes > maxFileBytes) {
        _rotateSync(file);
      }
    } on Exception {
      // dropped — see class doc
    }
  }

  static Future<void> _rotate(File file) async {
    try {
      final backup = File('${file.path}.1');
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    } on Exception {
      // fall through: append to the oversized file rather than lose lines
    }
    _fileBytes = 0;
  }

  static void _rotateSync(File file) {
    try {
      final backup = File('${file.path}.1');
      if (backup.existsSync()) backup.deleteSync();
      file.renameSync(backup.path);
    } on Exception {
      // as above
    }
    _fileBytes = 0;
  }

  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.info => 800,
    LogLevel.warn => 900,
    LogLevel.error => 1000,
  };
}
