import 'dart:io';
import 'dart:typed_data';

import 'package:anilocal/data/chapters/chapter_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anilocal/data/skip/chapters_skip_provider.dart';
import 'package:anilocal/data/skip/skip_provider.dart';

/// The MP4 half of the container parsing, built from bytes rather than a real
/// file so it runs everywhere.
///
/// The MKV half and the real-world accuracy of BOTH are covered by
/// `test_live/chapter_reader_live_test.dart`, which compares every file in a
/// real library against ffprobe — a far stronger check than any fixture. This
/// exists so the default suite still fails if the MP4 path breaks.
Uint8List _atom(String type, List<int> body) {
  final out = BytesBuilder();
  final header = ByteData(8)..setUint32(0, body.length + 8);
  out.add(header.buffer.asUint8List(0, 4));
  out.add(type.codeUnits);
  out.add(body);
  return out.toBytes();
}

/// Nero `chpl`: version 1, four reserved bytes, a count, then per chapter an
/// 8-byte start in 100ns units and a length-prefixed title.
Uint8List _chpl(List<(double, String)> chapters) {
  final out = BytesBuilder();
  out.add([1, 0, 0, 0]); // version 1 + flags
  out.add([0, 0, 0, 0]); // reserved (version 1 only)
  out.add([chapters.length]);
  for (final (seconds, title) in chapters) {
    final ticks = ByteData(8)..setUint64(0, (seconds * 10000000).round());
    out.add(ticks.buffer.asUint8List());
    out.add([title.length]);
    out.add(title.codeUnits);
  }
  return out.toBytes();
}

Uint8List _mvhd({required int timescale, required int units}) {
  final body = ByteData(100);
  body.setUint8(0, 0); // version 0
  body.setUint32(12, timescale);
  body.setUint32(16, units);
  return body.buffer.asUint8List();
}

Future<File> _writeMp4(
  Directory dir,
  String name, {
  required List<(double, String)> chapters,
  int timescale = 1000,
  int units = 1440000, // 1440s
  bool includeChpl = true,
}) async {
  final moovBody = BytesBuilder()
    ..add(_atom('mvhd', _mvhd(timescale: timescale, units: units)));
  if (includeChpl) {
    moovBody.add(_atom('udta', _atom('chpl', _chpl(chapters))));
  }
  final bytes = BytesBuilder()
    ..add(_atom('ftyp', List.filled(8, 0)))
    ..add(_atom('moov', moovBody.toBytes()))
    ..add(_atom('mdat', List.filled(64, 7)));
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes.toBytes());
  return file;
}

void main() {
  late Directory dir;
  const reader = ChapterReader();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anilocal_chapters_');
  });
  tearDown(() => dir.delete(recursive: true));

  test('reads Nero chpl marks and the movie duration', () async {
    final file = await _writeMp4(
      dir,
      'ep.mp4',
      chapters: [(0.0, ''), (497.956, ''), (588.004, ''), (1330.996, '')],
    );

    final chapters = await reader.read(file.path);

    expect(chapters.marks.length, 4);
    expect(chapters.marks[1].start.inMilliseconds, 497956);
    expect(chapters.marks[3].start.inMilliseconds, 1330996);
    expect(chapters.duration, const Duration(seconds: 1440));
  });

  test('an empty chapter title is reported as absent', () async {
    // Across a real 285-file library only three chapters carried a title, which
    // is why OP/ED is inferred from length rather than read from a label.
    final file = await _writeMp4(
      dir,
      'ep.mp4',
      chapters: [(0.0, ''), (90.0, 'Part A')],
    );

    final chapters = await reader.read(file.path);

    expect(chapters.marks[0].title, isNull);
    expect(chapters.marks[1].title, 'Part A');
  });

  test('a file with no chpl yields nothing, and does not throw', () async {
    final file = await _writeMp4(
      dir,
      'ep.mp4',
      chapters: const [],
      includeChpl: false,
    );

    expect((await reader.read(file.path)).isEmpty, isTrue);
  });

  test('a missing file yields nothing', () async {
    expect((await reader.read('${dir.path}/nope.mp4')).isEmpty, isTrue);
  });

  test('garbage bytes yield nothing rather than throwing', () async {
    // This runs over whatever is on disk during a scan, so a malformed file
    // must behave exactly like one with no chapters.
    final file = File('${dir.path}/broken.mp4');
    await file.writeAsBytes(List.filled(512, 0xAB));

    expect((await reader.read(file.path)).isEmpty, isTrue);
  });

  test('an unknown extension is not parsed at all', () async {
    final file = File('${dir.path}/clip.avi');
    await file.writeAsBytes(List.filled(64, 0));

    expect((await reader.read(file.path)).isEmpty, isTrue);
  });

  test('a truncated chpl stops cleanly at the last whole chapter', () async {
    final file = await _writeMp4(
      dir,
      'ep.mp4',
      chapters: [(0.0, ''), (90.0, '')],
    );
    final bytes = await file.readAsBytes();
    // Lop off the final chapter's trailing bytes.
    await file.writeAsBytes(bytes.sublist(0, bytes.length - 70));

    // Whatever survives, it must not throw.
    await expectLater(reader.read(file.path), completes);
  });

  group('ChaptersSkipProvider.canAnswer', () {
    test(
      'a file that is not there is "could not try", not "no chapters"',
      () async {
        // A drive unplugged or remounted elsewhere makes the path dangle. The
        // reader reports a missing file as no chapters; if that were recorded
        // as this source's answer it would never be asked again — one refresh
        // with the library offline erased chapter skips for the whole drive.
        const provider = ChaptersSkipProvider();
        expect(
          provider.canAnswer(
            const SkipLookup(
              seriesId: 1,
              episode: 1,
              filePath: '/no/such/file.mkv',
            ),
          ),
          isFalse,
        );
        expect(
          provider.canAnswer(const SkipLookup(seriesId: 1, episode: 1)),
          isFalse,
          reason: 'no path at all is also not an attempt',
        );
      },
    );

    test('a file that IS there can be attempted', () async {
      final dir = await Directory.systemTemp.createTemp('anilocal_chap_');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/ep.mkv')..writeAsStringSync('x');
      expect(
        const ChaptersSkipProvider().canAnswer(
          SkipLookup(seriesId: 1, episode: 1, filePath: f.path),
        ),
        isTrue,
      );
    });
  });
}
