import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/skip/skip_provider.dart';

/// The shape of a seeded library, for the report a perf run prints.
class SyntheticShape {
  const SyntheticShape({
    required this.folders,
    required this.series,
    required this.files,
    required this.pendingSeries,
    required this.skipAnswers,
    required this.watchRows,
  });
  final int folders;
  final int series;
  final int files;
  final int pendingSeries;
  final int skipAnswers;
  final int watchRows;

  @override
  String toString() =>
      '$series series · $files files · $folders folders · '
      '$pendingSeries pending · $skipAnswers skip answers · $watchRows watch rows';
}

/// Seeds a [CacheDatabase] with a library of any size, so the read path and
/// the scan can be MEASURED rather than reasoned about.
///
/// The shape follows the reference library scaled up: files spread evenly
/// over the series and round-robin over the folders, two skip answers per
/// episode (chapters + AniSkip, the built-in order), a watch-state row for a
/// fraction of the episodes. `pendingFraction` of the SERIES are left
/// unidentified — files with no `seriesId`, `pendingIdentification` set and a
/// parsed title — because that is the state a whole library is in during its
/// first scan, and the read path's cost there is not the same as afterwards.
///
/// Paths are synthetic (`/lib/f0/Show 12/…`); nothing on disk is touched, and
/// a test that resolves folders should inject a resolver that does not probe.
class SyntheticLibrary {
  static Future<SyntheticShape> seed(
    CacheDatabase db, {
    int folders = 3,
    int series = 600,
    int files = 8000,
    double pendingFraction = 0,
    double watchedFraction = 0.25,
    bool skipAnswers = true,
  }) async {
    for (var f = 0; f < folders; f++) {
      await db.insertFolder('/lib/f$f');
    }
    final pendingSeries = (series * pendingFraction).round();
    final perSeries = files ~/ series;
    final seriesRows = <CachedSeriesRow>[];
    final fileRows = <CachedFileRow>[];
    final skipRows = <SkipSourceAnswerRow>[];
    final watchRows = <WatchStateRow>[];
    var fileNo = 0;
    for (var s = 1; s <= series; s++) {
      final pending = s <= pendingSeries;
      final count = s == series ? files - fileNo : perSeries;
      if (!pending) {
        seriesRows.add(
          CachedSeriesRow(
            seriesId: s,
            romaji: 'Show $s',
            english: s.isEven ? 'Show $s (EN)' : null,
            nativeTitle: null,
            format: 'TV',
            episodeCount: count + (s % 3), // some shows have gaps
            coverImageUrl: 'https://cdn.example/$s.jpg',
            coverImagePath: '/art/$s.jpg',
          ),
        );
      }
      for (var e = 1; e <= count; e++) {
        fileNo++;
        final folder = '/lib/f${fileNo % folders}';
        fileRows.add(
          CachedFileRow(
            folderPath: folder,
            relativePath:
                'Show $s/Show $s - ${e.toString().padLeft(2, '0')}.mkv',
            fileSize: 700000000 + fileNo,
            modifiedAtMs: 1700000000000 + fileNo * 1000,
            seriesId: pending ? null : s,
            episodeNumber: e,
            parsedTitle: 'Show $s',
            matchScore: pending ? 0 : 1,
            releaseGroup: 'Grp',
            pendingIdentification: pending,
          ),
        );
        if (pending) continue;
        if (skipAnswers) {
          for (final source in kBuiltInSkipOrder) {
            skipRows.add(
              SkipSourceAnswerRow(
                seriesId: s,
                episode: e,
                source: source,
                introStartMs: source == kBuiltInSkipOrder.first ? 0 : 1500,
                introEndMs: 90000,
                outroStartMs: 1290000,
                outroEndMs: 1380000,
                askedAtMs: 1700000000000,
              ),
            );
          }
        }
        if (e <= (count * watchedFraction).round()) {
          watchRows.add(
            WatchStateRow(
              seriesId: s,
              episode: e,
              resumePositionMs: e.isEven ? 600000 : 0,
              durationMs: 1440000,
              watched: e.isOdd,
              watchedManual: false,
              updatedAtMs: 1700000000000 + fileNo,
            ),
          );
        }
      }
    }
    await db.applySync(
      seriesUpserts: seriesRows,
      fileUpserts: fileRows,
      removedKeys: const [],
    );
    if (skipRows.isNotEmpty) await db.upsertSkipAnswers(skipRows);
    for (final w in watchRows) {
      await db.upsertWatchState(w);
    }
    return SyntheticShape(
      folders: folders,
      series: series,
      files: fileRows.length,
      pendingSeries: pendingSeries,
      skipAnswers: skipRows.length,
      watchRows: watchRows.length,
    );
  }
}
