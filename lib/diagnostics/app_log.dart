import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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

  static final ListQueue<String> _ring = ListQueue<String>();
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
        await file.create(recursive: true); // exists from attach, even if idle
        _fileBytes = 0;
      }
      _file = file;
      // Anything logged before the file was attached is carried across.
      for (final line in _ring) {
        _append(line);
      }
      flush();
    } on Exception {
      _file = null; // ring-only; a logger must never take the app down
    }
  }

  static void info(String message) => _write(LogLevel.info, message);

  static void warn(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.warn, message, error: error, stack: stack);

  static void error(String message, {Object? error, StackTrace? stack}) =>
      _write(LogLevel.error, message, error: error, stack: stack);

  static final Map<String, int> _repeats = {};

  /// A warning that can happen once per FILE: the first occurrence is logged
  /// in full, then only the 10th, 100th, 1,000th… with the running count. A
  /// scan over a volume with a permission problem used to write one line per
  /// file — hundreds of lines that evicted everything else "Copy diagnostics"
  /// exists to capture, and a synchronous disk write each. [key] groups the
  /// repeats; [message] is the specific instance (path included).
  static void warnRepeated(String key, String message, {Object? error}) {
    final n = (_repeats[key] ?? 0) + 1;
    _repeats[key] = n;
    if (n == 1) {
      _write(LogLevel.warn, message, error: error);
    } else if (n == 10 || n == 100 || n == 1000 || n % 10000 == 0) {
      _write(LogLevel.warn, '$message ($n so far under "$key")', error: error);
    }
  }

  /// How many times [key] has been reported this run.
  static int repeatCount(String key) => _repeats[key] ?? 0;

  /// Everything the ring holds, joined — what "Copy diagnostics" pastes.
  static String dump() => _ring.join('\n');

  /// Forget everything. Tests only; production never resets.
  static void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _debug = false;
    _repeats.clear();
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
    if (_ring.length > ringCapacity) _ring.removeFirst();
    if (_debug) {
      developer.log(message, name: 'anilocal', level: _developerLevel(level));
    }
    // An error line races the crash it may be describing: it goes to disk at
    // once. Everything else is batched.
    if (_file != null) _append(line, urgent: level == LogLevel.error);
  }

  /// Lines waiting for the disk. Written in one go by [flush], which runs
  /// [flushDelay] after the first buffered line, immediately for an error,
  /// and on demand (the quit path). One synchronous write per line used to be
  /// the rule — right for a crash log, wrong once mpv's log stream and a scan
  /// over a bad volume produced hundreds of lines a minute.
  static final StringBuffer _pending = StringBuffer();
  static Timer? _flushTimer;
  static const Duration flushDelay = Duration(milliseconds: 250);

  static void _append(String line, {bool urgent = false}) {
    if (_file == null) return;
    _pending.writeln(line);
    if (urgent) {
      flush();
      return;
    }
    _flushTimer ??= Timer(flushDelay, flush);
  }

  /// Write everything buffered to the file now. Safe to call at any time;
  /// a no-op when nothing is pending or no file is attached.
  static void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final file = _file;
    if (file == null || _pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    try {
      // Synchronous: the quit path and an error line must land before the
      // process can go.
      file.writeAsStringSync(text, mode: FileMode.append, flush: false);
      _fileBytes += utf8.encode(text).length; // bytes, like the file
      if (_fileBytes > maxFileBytes) {
        _rotateSync(file);
        file.createSync(); // the live file exists, empty, right away
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
