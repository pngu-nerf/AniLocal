import 'dart:io';

import 'package:http/http.dart' as http;
import '../../diagnostics/app_log.dart';

/// Downloads and stores cover art on disk so offline browse shows real images.
///
/// Incremental: if the art file for an AniList ID already exists, it is reused
/// (no re-download). A failed download returns null — the series is still
/// cached (metadata), and the missing art is retried on a later scan.
class ArtCache {
  ArtCache({http.Client? httpClient, required this.directory})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Resolves the art directory (injected — the app passes the app-support
  /// location, tests/tools pass a temp dir; no path_provider coupling here).
  final Future<Directory> Function() directory;

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
  }) async {
    if (url == null || url.isEmpty) return null;
    final dir = await directory();
    final ext = _extensionOf(url);
    final file = File('${dir.path}/$seriesId$ext');

    // An unknown previous URL means "no opinion" — reuse, as before.
    final sameSource = cachedUrl == null || cachedUrl == url;
    if (sameSource && await file.exists() && await file.length() > 0) {
      return file.path; // already cached
    }

    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(response.bodyBytes, flush: true);
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
      AppLog.warn('Cover: download failed for $url', error: e);
      return null;
    }
  }

  String _extensionOf(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = clean.substring(dot);
    return ext.length <= 5 ? ext : '.jpg';
  }

  void dispose() => _http.close();
}
