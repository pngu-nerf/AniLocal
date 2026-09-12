import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../diagnostics/app_log.dart';
import '../../domain/chapter_skips.dart';

/// What a container told us about its chapters.
class FileChapters {
  const FileChapters({required this.marks, required this.duration});

  static const FileChapters none = FileChapters(
    marks: [],
    duration: Duration.zero,
  );

  final List<ChapterMark> marks;

  /// Needed to close the LAST chapter, which containers leave open-ended.
  final Duration duration;

  bool get isEmpty => marks.isEmpty || duration <= Duration.zero;
}

/// Reads chapter marks straight out of the container.
///
/// Parsed by hand rather than shelled out to `ffprobe`, which AniLocal cannot
/// ship, and rather than driving libmpv, which would mean spinning up a player
/// per file during a scan.
///
/// Cheap by construction: both formats keep chapters in a small header near the
/// start, and the parsers SEEK past the media payload using the sizes the
/// containers declare. A 650MB file costs a handful of reads, not a scan.
///
/// Every failure is a null/empty result, never a throw. A malformed or
/// unfamiliar file must simply yield no chapters — the same as a file that has
/// none — because this runs inside the fill path over whatever is on disk.
class ChapterReader {
  const ChapterReader();

  Future<FileChapters> read(String path) async {
    final file = File(path);
    RandomAccessFile? handle;
    try {
      if (!await file.exists()) return FileChapters.none;
      handle = await file.open();
      final length = await handle.length();
      final lower = path.toLowerCase();
      if (lower.endsWith('.mkv') || lower.endsWith('.webm')) {
        return await _readMatroska(handle, length);
      }
      if (lower.endsWith('.mp4') ||
          lower.endsWith('.m4v') ||
          lower.endsWith('.mov')) {
        return await _readMp4(handle, length);
      }
      return FileChapters.none;
    } on Exception catch (e) {
      // Unreadable or malformed -> simply no chapters. Logged with the PATH:
      // a permission denial (macOS TCC on a removable volume) lands here too,
      // and looked exactly like "this file has no chapters" until it was.
      AppLog.warn('Chapters: could not read $path', error: e);
      return FileChapters.none;
    } finally {
      await handle?.close();
    }
  }

  // ---------------------------------------------------------------- Matroska

  // EBML ids, as read WITH their length marker.
  static const int _idSegment = 0x18538067;
  static const int _idInfo = 0x1549A966;
  static const int _idChapters = 0x1043A770;
  static const int _idCluster = 0x1F43B675;
  static const int _idTimecodeScale = 0x2AD7B1;
  static const int _idDuration = 0x4489;
  static const int _idEditionEntry = 0x45B9;
  static const int _idEditionFlagDefault = 0x45DB;
  static const int _idChapterAtom = 0xB6;
  static const int _idChapterTimeStart = 0x91;
  static const int _idChapterTimeEnd = 0x92;
  static const int _idChapterFlagHidden = 0x98;
  static const int _idChapterString = 0x85;
  static const int _idChapterDisplay = 0x80;

  /// The most a header element we READ INTO MEMORY may claim to be. Chapters
  /// and Info are kilobytes; a size field beyond this is a corrupt or hostile
  /// file, and `f.read(size)` would otherwise try to allocate whatever it
  /// said — up to exabytes for an unknown-size marker — as an
  /// `OutOfMemoryError`, which is an Error and so escaped the catch below.
  static const int _maxHeaderElement = 16 << 20;

  Future<FileChapters> _readMatroska(RandomAccessFile f, int length) async {
    // EBML header, then the Segment whose children we want.
    await f.setPosition(0);
    if (await _readElementId(f) == null) return FileChapters.none;
    final headerSize = await _readVint(f);
    if (headerSize == null || headerSize.unknown) return FileChapters.none;
    await f.setPosition(await f.position() + headerSize.value);

    if (await _readElementId(f) != _idSegment) return FileChapters.none;
    final segmentSize = await _readVint(f);
    if (segmentSize == null) return FileChapters.none;
    final segmentStart = await f.position();
    // An unknown-size Segment is legal (a live-captured file); it simply runs
    // to the end of the file. A declared size past the end is clamped.
    final declaredEnd = segmentSize.unknown || segmentSize.value == 0
        ? length
        : segmentStart + segmentSize.value;
    final segmentEnd = declaredEnd > length ? length : declaredEnd;

    Uint8List? chapters;
    Uint8List? info;
    var offset = segmentStart;
    while (offset < segmentEnd) {
      await f.setPosition(offset);
      final id = await _readElementId(f);
      if (id == null) break;
      final size = await _readVint(f);
      // An unknown-size CHILD cannot be skipped over (its end is wherever the
      // next top-level id happens to be), so the walk stops here.
      if (size == null || size.unknown) break;
      final body = await f.position();
      if (id == _idChapters || id == _idInfo) {
        if (size.value > _maxHeaderElement || body + size.value > segmentEnd) {
          return FileChapters.none; // corrupt size: refuse rather than guess
        }
        await f.setPosition(body);
        final data = await f.read(size.value);
        if (id == _idChapters) {
          chapters = data;
        } else {
          info = data;
        }
      } else if (id == _idCluster) {
        // Media payload starts here; everything we want precedes it. (A file
        // that puts Chapters after the clusters is legal but vanishingly rare,
        // and walking megabytes of media to find out is not worth it.)
        break;
      }
      final next = body + size.value;
      if (next <= offset) break; // zero-length Void etc. — never loop forever
      offset = next;
    }
    if (chapters == null) return FileChapters.none;

    var scale = 1000000; // EBML default: milliseconds expressed in nanoseconds
    double? durationTicks;
    for (final child in _ebmlChildren(info ?? Uint8List(0))) {
      if (child.id == _idTimecodeScale) scale = _ebmlUint(child.data);
      if (child.id == _idDuration) durationTicks = _ebmlFloat(child.data);
    }
    // No Duration means the last chapter cannot be closed, and no caller has
    // a duration to lend (the fill path never opens the container itself), so
    // the file yields nothing rather than a guess.
    if (durationTicks == null) return FileChapters.none;
    final duration = Duration(
      microseconds: (durationTicks * scale / 1000).round(),
    );

    return FileChapters(
      marks: _marksOf(_pickEdition(chapters)),
      duration: duration,
    );
  }

  /// ONE edition's chapters. A file can carry several (an ordered "director's
  /// cut" edition beside the plain one), and reading them all interleaved two
  /// timelines into one list. The edition flagged default wins; otherwise the
  /// first — which is what a player shows.
  static Uint8List? _pickEdition(Uint8List chapters) {
    Uint8List? first;
    for (final edition in _ebmlChildren(chapters)) {
      if (edition.id != _idEditionEntry) continue;
      first ??= edition.data;
      for (final field in _ebmlChildren(edition.data)) {
        if (field.id == _idEditionFlagDefault && _ebmlUint(field.data) == 1) {
          return edition.data;
        }
      }
    }
    return first;
  }

  static List<ChapterMark> _marksOf(Uint8List? edition) {
    if (edition == null) return const [];
    final marks = <ChapterMark>[];
    for (final atom in _ebmlChildren(edition)) {
      if (atom.id != _idChapterAtom) continue;
      int? startNs;
      int? endNs;
      var hidden = false;
      String? title;
      for (final field in _ebmlChildren(atom.data)) {
        switch (field.id) {
          // Spec: ChapterTimeStart/End are nanoseconds and are NOT scaled.
          case _idChapterTimeStart:
            startNs = _ebmlUint(field.data);
          case _idChapterTimeEnd:
            endNs = _ebmlUint(field.data);
          case _idChapterFlagHidden:
            hidden = _ebmlUint(field.data) == 1;
          case _idChapterDisplay:
            for (final display in _ebmlChildren(field.data)) {
              if (display.id == _idChapterString) {
                // UTF-8 by spec; `String.fromCharCodes` read the bytes as
                // Latin-1 and mojibaked every non-ASCII title.
                title = utf8.decode(display.data, allowMalformed: true);
              }
            }
        }
      }
      // A hidden chapter is one the author does not want shown or navigated
      // to; it is not a boundary a viewer would skip to either.
      if (startNs == null || hidden) continue;
      marks.add(
        ChapterMark(
          start: Duration(microseconds: startNs ~/ 1000),
          end: endNs == null ? null : Duration(microseconds: endNs ~/ 1000),
          title: (title?.isEmpty ?? true) ? null : title,
        ),
      );
    }
    return marks;
  }

  Future<int?> _readElementId(RandomAccessFile f) async =>
      (await _readVint(f, keepMarker: true))?.value;

  /// EBML variable-length integer. [keepMarker] keeps the length bits, which is
  /// how element IDs are conventionally written. `unknown` is the all-ones
  /// value the spec reserves for "size not known".
  Future<({int value, bool unknown})?> _readVint(
    RandomAccessFile f, {
    bool keepMarker = false,
  }) async {
    final first = await f.read(1);
    if (first.isEmpty || first[0] == 0) return null;
    var mask = 0x80;
    var width = 1;
    while ((first[0] & mask) == 0) {
      mask >>= 1;
      width++;
      if (width > 8) return null;
    }
    var value = keepMarker ? first[0] : first[0] & (mask - 1);
    var allOnes = (first[0] & (mask - 1)) == mask - 1;
    if (width > 1) {
      final rest = await f.read(width - 1);
      if (rest.length != width - 1) return null;
      for (final byte in rest) {
        value = (value << 8) | byte;
        if (byte != 0xFF) allOnes = false;
      }
    }
    return (value: value, unknown: !keepMarker && allOnes);
  }

  /// Children of an EBML master element already held in memory.
  static List<({int id, Uint8List data})> _ebmlChildren(Uint8List buffer) {
    final out = <({int id, Uint8List data})>[];
    var i = 0;
    while (i < buffer.length) {
      final id = _vintAt(buffer, i, keepMarker: true);
      if (id == null) break;
      i += id.width;
      final size = _vintAt(buffer, i);
      if (size == null) break;
      i += size.width;
      final end = i + size.value;
      if (end > buffer.length) break; // truncated: keep what parsed so far
      out.add((id: id.value, data: Uint8List.sublistView(buffer, i, end)));
      i = end;
    }
    return out;
  }

  static ({int value, int width})? _vintAt(
    Uint8List b,
    int i, {
    bool keepMarker = false,
  }) {
    if (i >= b.length || b[i] == 0) return null;
    var mask = 0x80;
    var width = 1;
    while ((b[i] & mask) == 0) {
      mask >>= 1;
      width++;
      if (width > 8) return null;
    }
    if (i + width > b.length) return null;
    var value = keepMarker ? b[i] : b[i] & (mask - 1);
    for (var k = 1; k < width; k++) {
      value = (value << 8) | b[i + k];
    }
    return (value: value, width: width);
  }

  static int _ebmlUint(Uint8List b) {
    var value = 0;
    for (final byte in b) {
      value = (value << 8) | byte;
    }
    return value;
  }

  static double _ebmlFloat(Uint8List b) {
    final view = ByteData.sublistView(b);
    if (b.length == 4) return view.getFloat32(0);
    if (b.length == 8) return view.getFloat64(0);
    return 0;
  }

  // --------------------------------------------------------------------- MP4

  Future<FileChapters> _readMp4(RandomAccessFile f, int length) async {
    final moov = await _findAtom(f, 0, length, const ['moov']);
    if (moov == null) return FileChapters.none;

    final mvhd = await _findAtom(f, moov.body, moov.end, const ['mvhd']);
    if (mvhd == null) return FileChapters.none;
    await f.setPosition(mvhd.body);
    final header = await f.read(mvhd.end - mvhd.body);
    final duration = _mp4Duration(header);
    if (duration == null) return FileChapters.none;

    // Nero-style chapter list. The other MP4 conventions (a text track wired up
    // through tref/chap) are not read: `chpl` is what the releases in the
    // reference library actually carry, and inventing support for a form we
    // have never seen would be untested code.
    final chpl = await _findAtom(f, moov.body, moov.end, const [
      'udta',
      'chpl',
    ]);
    if (chpl == null) return FileChapters.none;
    await f.setPosition(chpl.body);
    final payload = await f.read(chpl.end - chpl.body);
    return FileChapters(marks: _parseChpl(payload), duration: duration);
  }

  static Duration? _mp4Duration(Uint8List mvhd) {
    if (mvhd.length < 20) return null;
    final view = ByteData.sublistView(mvhd);
    final version = mvhd[0];
    // v1 widens the creation/modification times and the duration to 64 bits.
    final int timescale;
    final int units;
    if (version == 1) {
      if (mvhd.length < 32) return null;
      timescale = view.getUint32(20);
      units = view.getUint64(24);
    } else {
      timescale = view.getUint32(12);
      units = view.getUint32(16);
    }
    if (timescale == 0) return null;
    return Duration(microseconds: (units * 1000000 / timescale).round());
  }

  static List<ChapterMark> _parseChpl(Uint8List b) {
    if (b.length < 5) return const [];
    final version = b[0];
    // version + flags, then a reserved word that only version 1 carries.
    var i = 4 + (version == 1 ? 4 : 0);
    if (i >= b.length) return const [];
    final count = b[i];
    i += 1;
    final view = ByteData.sublistView(b);
    final marks = <ChapterMark>[];
    for (var n = 0; n < count; n++) {
      if (i + 9 > b.length) break;
      // Start time in 100-nanosecond units.
      final ticks = view.getUint64(i);
      i += 8;
      final titleLength = b[i];
      i += 1;
      if (i + titleLength > b.length) break;
      // UTF-8 by spec (Nero writes it so); Latin-1 mojibaked non-ASCII.
      final title = utf8.decode(
        Uint8List.sublistView(b, i, i + titleLength),
        allowMalformed: true,
      );
      i += titleLength;
      marks.add(
        ChapterMark(
          start: Duration(microseconds: ticks ~/ 10),
          title: title.isEmpty ? null : title,
        ),
      );
    }
    return marks;
  }

  /// Walk the atom tree to [path], returning where its payload lives.
  Future<({int body, int end})?> _findAtom(
    RandomAccessFile f,
    int start,
    int limit,
    List<String> path,
  ) async {
    var offset = start;
    while (offset + 8 <= limit) {
      await f.setPosition(offset);
      final header = await f.read(8);
      if (header.length < 8) return null;
      final view = ByteData.sublistView(header);
      var size = view.getUint32(0);
      var headerSize = 8;
      if (size == 1) {
        final extended = await f.read(8);
        if (extended.length < 8) return null;
        size = ByteData.sublistView(extended).getUint64(0);
        headerSize = 16;
      } else if (size == 0) {
        size = limit - offset; // "to end of file"
      }
      // A bad atom ends THIS level's walk; it does not abandon the file. One
      // corrupt atom before `moov` used to lose every chapter.
      if (size < headerSize) break;
      final name = String.fromCharCodes(header.sublist(4, 8));
      if (name == path.first) {
        final body = offset + headerSize;
        final end = offset + size;
        if (path.length == 1) return (body: body, end: end);
        final found = await _findAtom(f, body, end, path.sublist(1));
        if (found != null) return found;
      }
      offset += size;
    }
    return null;
  }
}
