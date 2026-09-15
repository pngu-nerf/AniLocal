import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/cache/skip_view_source.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/counting_executor.dart';
import 'support/fake_volume_resolver.dart';
import 'support/synthetic_library.dart';

/// The SHAPE of the read path, pinned by statement counts — exact numbers
/// that hold on any machine, unlike the timings in test/perf. Two contracts:
///
/// 1. A library-wide read loads each table ONCE. `snapshot()` is the library
///    screen's whole reload; it used to be five reads that each loaded
///    `file_cache` again.
/// 2. A per-series read costs one series, not the library: the statement
///    count for `episodesFor` / `nextEpisode` / `seriesById` does not change
///    when the library is ten times larger, and none of them touches the
///    whole `file_cache`.
///
/// Reverting either optimisation turns these red (mutation-checked).
void main() {
  Future<
    ({DriftLibraryRepository repo, CountingInterceptor n, CacheDatabase db})
  >
  build({required int series, required int files, double pending = 0}) async {
    final n = CountingInterceptor();
    final db = CacheDatabase(NativeDatabase.memory().interceptWith(n));
    await SyntheticLibrary.seed(
      db,
      series: series,
      files: files,
      pendingFraction: pending,
    );
    final repo = DriftLibraryRepository(
      db,
      skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
      resolver: FakeVolumeResolver(),
    );
    n.reset();
    return (repo: repo, n: n, db: db);
  }

  group('the read path loads each table once', () {
    test('snapshot() is one pass: ten selects, file_cache once', () async {
      final r = await build(series: 30, files: 300);
      addTearDown(r.db.close);
      await r.repo.snapshot();
      expect(r.n.selects, 10, reason: r.n.summary());
      expect(r.n.byTable['file_cache'], 1);
      expect(r.n.byTable['watch_state'], 1);
      expect(r.n.byTable['skip_source_answers'], 1);
    });

    test('a first-scan snapshot (every show pending) costs the same', () async {
      // The placeholder pass used to re-load two tables PER pending show:
      // 600 pending shows = 1,200 extra selects. Now it is part of the one
      // pass, so the count does not depend on how many shows are pending.
      final identified = await build(series: 30, files: 300);
      addTearDown(identified.db.close);
      await identified.repo.snapshot();
      final pending = await build(series: 30, files: 300, pending: 1);
      addTearDown(pending.db.close);
      final snap = await pending.repo.snapshot();
      expect(snap.series, hasLength(30));
      expect(snap.series.every((s) => s.pending), isTrue);
      expect(
        pending.n.selects,
        identified.n.selects,
        reason: pending.n.summary(),
      );
    });

    test('unmatchedCount is one COUNT, no rows', () async {
      final r = await build(series: 30, files: 300);
      addTearDown(r.db.close);
      expect(await r.repo.unmatchedCount(), 0);
      expect(r.n.selects, 1);
    });
  });

  group('a per-series read costs one series', () {
    test('episodesFor / nextEpisode / seriesById do not scan file_cache and '
        'issue the same statements at 10× the library', () async {
      final small = await build(series: 20, files: 200);
      addTearDown(small.db.close);
      final large = await build(series: 200, files: 2000);
      addTearDown(large.db.close);

      Future<(int, int, Map<String, int>)> cost(
        ({DriftLibraryRepository repo, CountingInterceptor n, CacheDatabase db})
        r,
        Future<void> Function() read,
      ) async {
        r.n.reset();
        await read();
        return (r.n.selects, r.n.rowsRead, Map.of(r.n.byTable));
      }

      for (final read in [
        (DriftLibraryRepository repo) => repo.episodesFor(7),
        (DriftLibraryRepository repo) async =>
            repo.nextEpisode((await repo.episodesFor(7)).first),
        (DriftLibraryRepository repo) => repo.seriesById(7),
      ]) {
        final (a, aRows, aTables) = await cost(small, () => read(small.repo));
        final (b, bRows, bTables) = await cost(large, () => read(large.repo));
        expect(b, a, reason: 'statements must not grow with the library');
        expect(aTables, bTables);
        // The number that tells one series from the whole library: a per-
        // series load reads this series' 10 files and their side rows by
        // index; a whole-library load would read 2,000 files here.
        expect(
          bRows,
          aRows,
          reason: 'rows read must not grow with the library',
        );
        expect(bRows, lessThan(200), reason: 'one show, not the library');
      }
      final eps = await large.repo.episodesFor(7);
      expect(eps, hasLength(10));
    });

    test('the whole per-series read is under a dozen statements', () async {
      final r = await build(series: 50, files: 500);
      addTearDown(r.db.close);
      await r.repo.episodesFor(7);
      expect(r.n.selects, lessThanOrEqualTo(12), reason: r.n.summary());
    });
  });

  group('the scan prunes once', () {
    test('a batch commit with prune: false issues no DELETE', () async {
      final r = await build(series: 5, files: 50);
      addTearDown(r.db.close);
      await r.db.applySync(
        seriesUpserts: const [],
        fileUpserts: const [],
        removedKeys: const [],
        prune: false,
      );
      expect(r.n.deletes + r.n.customs, 0, reason: r.n.summary());
      r.n.reset();
      await r.db.pruneOrphans();
      expect(r.n.customs, 3, reason: 'the three orphan sweeps, once');
    });
  });
}
