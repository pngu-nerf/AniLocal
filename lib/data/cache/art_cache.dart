import 'dart:io';

import 'package:http/http.dart' as http;

import '../../diagnostics/app_log.dart';
import '../user_agent.dart';

/// Downloads and stores cover art on disk so offline browse shows real images.
///
/// Incremental: if the art file for a series is already on disk, it is reused
/// (no re-download). A failed download returns null — the series is still
/// cached (metadata), and the missing art is retried on a later scan.
///
/// Files are named `<series_id><ext>` under [directory], where the id is OUR
/// surrogate, never a provider's. That is what lets [deleteExcept] sweep art
/// for shows the cache no longer holds.
class ArtCache {
  ArtCache({http.Client? httpClient, required this.directory})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Resolves the art directory (injected — the app passes the app-support
  /// location, tests/tools pass a temp dir; no path_provider coupling here).
  final Future<Directory> Function() directory;

  /// Downloads in flight, by series id. Two callers asking for the same cover
  /// at once (a scan and a fix-match) share one request instead of writing
  /// the same file twice.
  final _inFlight = <int, Future<String?>>{};

  /// The extensions a cover may be stored under. Anything else — including a
  /// URL whose "extension" is a path fragment like `.a/b` — becomes `.jpg`,
  /// so the name we write is always a plain file in [directory].
  static const _extensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

  /// Ensure cover art for [seriesId] is on disk; return its local path (or
  /// null on failure / no URL).
  ///
  /// [cachedUrl] and [cachedPath] are what we last stored for this series. Pass
  /// them and a cover whose SOURCE URL has changed is re-downloaded — otherwise
  /// the "file already exists" short-circuit would pin the first source's art
  /// forever, so switching metadata sources would update every field except the
  /// picture. Omit them for the plain reuse behaviour.
  Future<String?> ensureCover(
    int seriesId,
    String? url, {
    String? cachedUrl,
    String? cachedPath,
  }) {
    if (url == null || url.isEmpty) return Future.value();
    // Block body on purpose: `whenComplete(() => _inFlight.remove(id))`
    // would RETURN the removed future — this very one — and wait on itself
    // forever.
    return _inFlight[seriesId] ??=
        _ensure(
          seriesId,
          url,
          cachedUrl: cachedUrl,
          cachedPath: cachedPath,
        ).whenComplete(() {
          // The removed future is this one; `ignore()` says so explicitly.
          _inFlight.remove(seriesId)?.ignore();
        });
  }

  Future<String?> _ensure(
    int seriesId,
    String url, {
    required String? cachedUrl,
    required String? cachedPath,
  }) async {
    final dir = await directory();
    final ext = _extensionOf(url);
    final file = File('${dir.path}/$seriesId$ext');

    // An unknown previous URL means "no opinion" — reuse, as before — but
    // only a file that IS an image: an HTML error page saved under .jpg used
    // to be reused forever.
    final sameSource = cachedUrl == null || cachedUrl == url;
    if (sameSource && await _isImageFile(file)) {
      return file.path; // already cached
    }

    try {
      final response = await _http.get(
        Uri.parse(url),
        // The one HTTP caller that went out without a UA: AniList's CDN sits
        // behind the same edge that 403s package:http's default.
        headers: {'User-Agent': aniLocalUserAgent},
      );
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      if (!looksLikeImage(response.bodyBytes)) {
        // A 200 that is not a picture: a captive portal, an error page, a
        // CDN interstitial. Nothing is written, so it is retried next scan.
        AppLog.warnRepeated(
          'cover-not-image',
          'Cover: $url did not return an image (${response.bodyBytes.length} bytes)',
        );
        return null;
      }
      // Write beside, then rename into place: a crash or a truncated body
      // mid-write used to leave a partial image at the canonical name, which
      // the reuse check above then accepted forever.
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(file.path);
      // A different source can use a different extension, so the replacement
      // may live at a new path. Drop the superseded file rather than orphaning
      // it — only ever the one we ourselves recorded.
      if (cachedPath != null && cachedPath != file.path) {
        try {
          final stale = File(cachedPath);
          if (await stale.exists()) await stale.delete();
        } on Exception catch (e) {
          // A leftover file is harmless; failing the refresh over it is not.
          AppLog.warn('Cover: could not delete stale $cachedPath', error: e);
        }
      }
      return file.path;
    } on Exception catch (e) {
      // Metadata still cached; art retried next scan. Logged, because a cover
      // that fails forever used to be invisible — a grey box with no trail.
      AppLog.warnRepeated(
        'cover-download',
        'Cover: download failed for $url',
        error: e,
      );
      return null;
    }
  }

  /// Delete every cover whose series id is not in [keep]. Returns how many
  /// went. Called after a scan that finished and applied its removals, so a
  /// library churned over years does not accumulate art for shows that no
  /// longer exist; nothing else ever deleted a cover except its replacement.
  Future<int> deleteExcept(Set<int> keep) async {
    final Directory dir;
    try {
      dir = await directory();
      if (!await dir.exists()) return 0;
    } on Exception catch (e) {
      // A sweep is housekeeping; an art directory that cannot be reached
      // right now is not a reason to fail the scan that just finished.
      AppLog.warn('Cover: sweep skipped, art directory unavailable', error: e);
      return 0;
    }
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      // A `.part` is a download that never finished (the app quit mid-way);
      // nothing reuses it, so it goes.
      if (name.endsWith('.part')) {
        try {
          await entity.delete();
          removed++;
        } on Exception catch (e) {
          AppLog.warn('Cover: could not delete ${entity.path}', error: e);
        }
        continue;
      }
      final dot = name.lastIndexOf('.');
      final id = int.tryParse(dot < 0 ? name : name.substring(0, dot));
      // Not one of ours (a stray `.DS_Store`): only a bare integer stem is a
      // cover.
      if (id == null || keep.contains(id)) continue;
      try {
        await entity.delete();
        removed++;
      } on Exception catch (e) {
        AppLog.warn('Cover: could not delete ${entity.path}', error: e);
      }
    }
    return removed;
  }

  static String _extensionOf(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = clean.substring(dot).toLowerCase();
    return _extensions.contains(ext) ? ext : '.jpg';
  }

  /// The client is injected and owned by the composition root; this closes
  /// only a client this cache constructed itself.
  void dispose() {}
}

/// Whether [bytes] begin like an image this app can show: JPEG, PNG, GIF or
/// WebP magic. Checked on download and on reuse, so a non-image never pins
/// itself under a cover's name.
bool looksLikeImage(List<int> bytes) {
  if (bytes.length < 12) return false;
  bool at(int i, List<int> sig) {
    for (var k = 0; k < sig.length; k++) {
      if (bytes[i + k] != sig[k]) return false;
    }
    return true;
  }

  return at(0, const [0xFF, 0xD8, 0xFF]) || // JPEG
      at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) || // PNG
      at(0, const [0x47, 0x49, 0x46, 0x38]) || // GIF8
      (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
          at(8, const [0x57, 0x45, 0x42, 0x50])); // RIFF….WEBP
}

Future<bool> _isImageFile(File file) async {
  try {
    if (!await file.exists()) return false;
    final handle = await file.open();
    try {
      return looksLikeImage(await handle.read(12));
    } finally {
      await handle.close();
    }
  } on Exception {
    return false;
  }
}
