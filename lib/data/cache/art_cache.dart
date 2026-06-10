import 'dart:io';

import 'package:http/http.dart' as http;

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

  /// Ensure cover art for [anilistId] is on disk; return its local path (or
  /// null on failure / no URL).
  Future<String?> ensureCover(int anilistId, String? url) async {
    if (url == null || url.isEmpty) return null;
    final dir = await directory();
    final ext = _extensionOf(url);
    final file = File('${dir.path}/$anilistId$ext');

    if (await file.exists() && await file.length() > 0) {
      return file.path; // already cached
    }

    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } on Exception {
      return null; // metadata still cached; art retried next scan
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
