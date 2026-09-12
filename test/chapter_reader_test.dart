import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anilocal/data/chapters/chapter_reader.dart';
import 'package:anilocal/data/skip/chapters_skip_provider.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:flutter_test/flutter_test.dart';

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

// ------------------------------------------------------------------ Matroska
//
// EBML fixtures built by hand: element id (with its length marker), a
// variable-length size, then the body. Enough of the container to exercise
// every branch of the walk without a real file.

Uint8List _vint(int value, {int? width}) {
  var w = width ?? 1;
  if (width == null) {
    while (value >= (1 << (7 * w)) - 1 && w < 8) {
      w++;
    }
  }
  final out = Uint8List(w);
  var v = value;
  for (var k = w - 1; k >= 0; k--) {
    out[k] = v & 0xFF;
    v >>= 8;
  }
  out[0] |= 0x80 >> (w - 1);
  return out;
}

/// The all-ones marker the spec reserves for "size unknown".
Uint8List _unknownSize() => Uint8List.fromList([0xFF]);

Uint8List _idBytes(int id) {
  final out = <int>[];
  var v = id;
  while (v > 0) {
    out.insert(0, v & 0xFF);
    v >>= 8;
  }
  return Uint8List.fromList(out);
}

Uint8List _ebml(int id, List<int> body, {Uint8List? size}) {
  final out = BytesBuilder()
    ..add(_idBytes(id))
    ..add(size ?? _vint(body.length))
    ..add(body);
  return out.toBytes();
}

Uint8List _uint(int v) {
  final out = <int>[];
  do {
    out.insert(0, v & 0xFF);
    v >>= 8;
  } while (v > 0);
  return Uint8List.fromList(out);
}

Uint8List _float64(double v) =>
    (ByteData(8)..setFloat64(0, v)).buffer.asUint8List();

Uint8List _atomMkv({
  required Duration start,
  Duration? end,
  String? title,
  bool hidden = false,
}) => _ebml(0xB6, [
  ..._ebml(0x91, _uint(start.inMicroseconds * 1000)),
  if (end != null) ..._ebml(0x92, _uint(end.inMicroseconds * 1000)),
  if (hidden) ..._ebml(0x98, [1]),
  if (title != null) ..._ebml(0x80, _ebml(0x85, utf8.encode(title))),
]);

Uint8List _edition(List<Uint8List> atoms, {bool isDefault = false}) =>
    _ebml(0x45B9, [
      if (isDefault) ..._ebml(0x45DB, [1]),
      for (final a in atoms) ...a,
    ]);

/// A whole file: EBML header, then a Segment holding Info (scale + duration),
/// Chapters (the given editions) and a Cluster. [chaptersSize] overrides the
/// declared size of the Chapters element to build corrupt files.
Uint8List _mkv({
  required List<Uint8List> editions,
  Duration duration = const Duration(minutes: 24),
  Uint8List? chaptersSize,
  bool withInfo = true,
}) {
  final info = _ebml(0x1549A966, [
    ..._ebml(0x2AD7B1, _uint(1000000)),
    ..._ebml(0x4489, _float64(duration.inMilliseconds.toDouble())),
  ]);
  final chapters = _ebml(0x1043A770, [
    for (final e in editions) ...e,
  ], size: chaptersSize);
  final cluster = _ebml(0x1F43B675, List.filled(32, 0));
  final segment = _ebml(0x18538067, [
    if (withInfo) ...info,
    ...chapters,
    ...cluster,
  ]);
  return (BytesBuilder()
        ..add(_ebml(0x1A45DFA3, _ebml(0x4286, [1])))
        ..add(segment))
      .toBytes();
}

void main() {
  late Directory dir;
  const reader = ChapterReader();

  Future<File> writeMkv(String name, Uint8List bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

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

  group('Matroska', () {
    test(
      'reads marks, the duration, an explicit end and a UTF-8 title',
      () async {
        final f = await writeMkv(
          'ok.mkv',
          _mkv(
            editions: [
              _edition([
                _atomMkv(start: Duration.zero, title: 'オープニング'),
                _atomMkv(
                  start: const Duration(seconds: 90),
                  end: const Duration(seconds: 100),
                ),
                _atomMkv(start: const Duration(seconds: 200)),
              ]),
            ],
          ),
        );
        final c = await reader.read(f.path);
        expect(c.duration, const Duration(minutes: 24));
        expect(c.marks.map((m) => m.start.inSeconds), [0, 90, 200]);
        expect(c.marks.first.title, 'オープニング', reason: 'UTF-8, not Latin-1');
        expect(c.marks[1].end, const Duration(seconds: 100));
        expect(c.marks[2].end, isNull);
      },
    );

    test('a hidden chapter is not a boundary', () async {
      final f = await writeMkv(
        'hidden.mkv',
        _mkv(
          editions: [
            _edition([
              _atomMkv(start: Duration.zero),
              _atomMkv(start: const Duration(seconds: 5), hidden: true),
              _atomMkv(start: const Duration(seconds: 90)),
            ]),
          ],
        ),
      );
      expect((await reader.read(f.path)).marks.map((m) => m.start.inSeconds), [
        0,
        90,
      ]);
    });

    test('several editions: the DEFAULT one, never both interleaved', () async {
      final f = await writeMkv(
        'editions.mkv',
        _mkv(
          editions: [
            _edition([
              _atomMkv(start: Duration.zero),
              _atomMkv(start: const Duration(seconds: 500)),
            ]),
            _edition([
              _atomMkv(start: Duration.zero),
              _atomMkv(start: const Duration(seconds: 90)),
            ], isDefault: true),
          ],
        ),
      );
      expect(
        (await reader.read(f.path)).marks.map((m) => m.start.inSeconds),
        [0, 90],
        reason: 'the flagged edition wins',
      );
    });

    test('with no default flag the FIRST edition is read', () async {
      final f = await writeMkv(
        'first.mkv',
        _mkv(
          editions: [
            _edition([_atomMkv(start: const Duration(seconds: 7))]),
            _edition([_atomMkv(start: const Duration(seconds: 8))]),
          ],
        ),
      );
      expect((await reader.read(f.path)).marks.single.start.inSeconds, 7);
    });

    test('a Chapters element claiming an absurd size yields nothing', () async {
      // The size field says 7 exabytes; `read(size)` would have asked for
      // that allocation — an OutOfMemoryError past the `on Exception`.
      final f = await writeMkv(
        'huge.mkv',
        _mkv(
          editions: [
            _edition([_atomMkv(start: Duration.zero)]),
          ],
          chaptersSize: _vint(0x00FFFFFFFFFFFF, width: 8),
        ),
      );
      expect((await reader.read(f.path)).isEmpty, isTrue);
    });

    test('an unknown-size child stops the walk cleanly', () async {
      final f = await writeMkv(
        'unknown.mkv',
        _mkv(
          editions: [
            _edition([_atomMkv(start: Duration.zero)]),
          ],
          chaptersSize: _unknownSize(),
        ),
      );
      expect((await reader.read(f.path)).isEmpty, isTrue);
    });

    test('a file truncated inside Chapters keeps the whole atoms', () async {
      final full = _mkv(
        editions: [
          _edition([
            _atomMkv(start: Duration.zero),
            _atomMkv(start: const Duration(seconds: 90)),
          ]),
        ],
      );
      // Cut the file a few bytes into the Cluster: Chapters is intact but the
      // declared Segment size now runs past the end.
      final cut = full.sublist(0, full.length - 20);
      final f = await writeMkv('truncated.mkv', cut);
      expect((await reader.read(f.path)).marks.map((m) => m.start.inSeconds), [
        0,
        90,
      ]);
    });

    test('no Info/Duration means nothing, never a guess', () async {
      final f = await writeMkv(
        'noinfo.mkv',
        _mkv(
          editions: [
            _edition([_atomMkv(start: Duration.zero)]),
          ],
          withInfo: false,
        ),
      );
      expect((await reader.read(f.path)).isEmpty, isTrue);
    });
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
