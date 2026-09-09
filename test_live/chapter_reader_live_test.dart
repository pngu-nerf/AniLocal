import 'dart:convert';
import 'dart:io';

import 'package:anilocal/data/chapters/chapter_reader.dart';
import 'package:anilocal/domain/chapter_skips.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the REAL container parsers over the REAL library and checks them
/// against ffprobe, which is the only independent authority available.
///
/// Outside `test/` so it never runs in the normal suite: it needs a mounted
/// library and an ffprobe on PATH, neither of which CI or another machine has.
///
///   flutter test test_live/chapter_reader_live_test.dart
///
/// Hand-written binary parsers are exactly the code where "it compiles and the
/// unit tests pass" proves least, so this exists to compare against reality.
const String _root = '/Volumes/Anime';

List<double> _ffprobeStarts(String path) {
  final out = Process.runSync('ffprobe', [
    '-v',
    'quiet',
    '-print_format',
    'json',
    '-show_chapters',
    path,
  ]);
  final chapters =
      (jsonDecode(out.stdout as String) as Map)['chapters'] as List? ?? [];
  return [
    for (final c in chapters) double.parse((c as Map)['start_time'] as String),
  ];
}

double? _ffprobeDuration(String path) {
  final out = Process.runSync('ffprobe', [
    '-v',
    'quiet',
    '-print_format',
    'json',
    '-show_format',
    path,
  ]);
  final format = (jsonDecode(out.stdout as String) as Map)['format'] as Map?;
  final raw = format?['duration'] as String?;
  return raw == null ? null : double.parse(raw);
}

void main() {
  final root = Directory(_root);
  if (!root.existsSync()) {
    test('LIVE: library not mounted', () => fail('$_root is not mounted'));
    return;
  }

  // Walked by hand: a recursive listSync dies on macOS system directories a
  // volume carries (.Spotlight-V100, .fseventsd) with "Operation not
  // permitted", which the app's own scanner already steps around.
  final files = <File>[];
  void walk(Directory dir) {
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync();
    } on FileSystemException {
      return; // unreadable directory — skip it, exactly as a scan would
    }
    for (final entry in entries) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      if (entry is Directory) {
        walk(entry);
      } else if (entry is File) {
        final lower = entry.path.toLowerCase();
        if (lower.endsWith('.mkv') || lower.endsWith('.mp4')) files.add(entry);
      }
    }
  }

  walk(root);
  files.sort((a, b) => a.path.compareTo(b.path));

  test(
    'LIVE: parsed chapter marks match ffprobe, file for file',
    () async {
      const reader = ChapterReader();
      var compared = 0;
      var withChapters = 0;
      final mismatches = <String>[];

      for (final file in files) {
        final expected = _ffprobeStarts(file.path);
        final actual = await reader.read(file.path);
        compared++;
        if (expected.isEmpty) {
          if (actual.marks.isNotEmpty) {
            mismatches.add('${file.path}: we found chapters, ffprobe did not');
          }
          continue;
        }
        withChapters++;
        if (actual.marks.length != expected.length) {
          mismatches.add(
            '${file.path}: ${actual.marks.length} marks vs ffprobe '
            '${expected.length}',
          );
          continue;
        }
        for (var i = 0; i < expected.length; i++) {
          final ours = actual.marks[i].start.inMilliseconds / 1000.0;
          if ((ours - expected[i]).abs() > 0.05) {
            mismatches.add('${file.path}: mark $i $ours vs ${expected[i]}');
          }
        }
        final duration = _ffprobeDuration(file.path);
        if (duration != null) {
          final ours = actual.duration.inMilliseconds / 1000.0;
          if ((ours - duration).abs() > 1.0) {
            mismatches.add('${file.path}: duration $ours vs $duration');
          }
        }
      }

      // ignore: avoid_print
      print('  compared $compared files, $withChapters with chapters');
      expect(compared, greaterThan(0), reason: 'no media found to compare');
      expect(
        withChapters,
        greaterThan(0),
        reason: 'nothing exercised the parser',
      );
      expect(mismatches, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'LIVE: inferred OP/ED windows look like openings',
    () async {
      const reader = ChapterReader();
      var inferred = 0;
      final wrongLength = <String>[];

      for (final file in files) {
        final chapters = await reader.read(file.path);
        if (chapters.isEmpty) continue;
        final skips = inferSkipsFromChapters(chapters.marks, chapters.duration);
        if (skips == null) continue;
        inferred++;
        for (final window in [skips.intro, skips.outro]) {
          if (window == null) continue;
          final length = window.end - window.start;
          if (length < kOpeningMinLength || length > kOpeningMaxLength) {
            wrongLength.add('${file.path}: ${length.inSeconds}s');
          }
          if (window.end > chapters.duration) {
            wrongLength.add('${file.path}: window past end of file');
          }
        }
      }

      // ignore: avoid_print
      print('  inferred skip windows for $inferred files');
      expect(inferred, greaterThan(0));
      expect(wrongLength, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
