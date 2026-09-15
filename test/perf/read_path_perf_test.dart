@Tags(['perf'])
library;

import 'dart:io';

import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:anilocal/data/cache/skip_view_source.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/domain/models/next_result.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/counting_executor.dart';
import '../support/fake_volume_resolver.dart';
import '../support/synthetic_library.dart';

/// The read path, measured. NOT part of the gate (tagged `perf`, excluded in
/// tool/check.sh): it asserts nothing about time, because a number that fails
/// on a slow CI runner teaches nothing. It PRINTS a table; `tool/perf.sh`
/// runs it and the numbers are recorded, dated, in docs/performance.md, where
/// before and after sit side by side.
///
/// Statement counts ARE exact and are the part worth asserting once the read
/// path has been reshaped — see the notes in docs/performance.md.
void main() {
  const series = 600;
  const files = 8000;

  Future<
    ({CacheDatabase db, DriftLibraryRepository repo, CountingInterceptor n})
  >
  build({double pendingFraction = 0}) async {
    final n = CountingInterceptor();
    final db = CacheDatabase(NativeDatabase.memory().interceptWith(n));
    final shape = await SyntheticLibrary.seed(
      db,
      series: series,
      files: files,
      pendingFraction: pendingFraction,
    );
    // ignore: avoid_print
    print('  seeded: $shape');
    final repo = DriftLibraryRepository(
      db,
      skipView: SkipViewSource.fixed(order: kBuiltInSkipOrder),
      resolver: FakeVolumeResolver(),
    );
    n.reset();
    return (db: db, repo: repo, n: n);
  }

  final rows = <String>[];

  Future<T> measure<T>(
    String label,
    CountingInterceptor n,
    Future<T> Function() run,
  ) async {
    n.reset();
    final sw = Stopwatch()..start();
    final out = await run();
    sw.stop();
    final line =
        '| $label | ${sw.elapsedMilliseconds} ms | ${n.statements} | '
        '${n.byTable.entries.map((e) => '${e.key}×${e.value}').join(', ')} |';
    rows.add(line);
    return out;
  }

  tearDownAll(() {
    final header = [
      '',
      'PERF TABLE — read path at S=$series / F=$files, in-memory SQLite, '
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
          '${Platform.numberOfProcessors} cores, ${DateTime.now().toIso8601String().substring(0, 10)}',
      '',
      '| operation | wall | statements | by table |',
      '|---|---|---|---|',
    ];
    // ignore: avoid_print
    print([...header, ...rows, 'END PERF'].join('\n'));
  });

  test('every read, library fully identified', () async {
    final r = await build();
    addTearDown(r.db.close);
    final all = await measure('allSeries', r.n, r.repo.allSeries);
    expect(all, hasLength(series));
    final bySeries = await measure(
      'episodesBySeries (P=0)',
      r.n,
      r.repo.episodesBySeries,
    );
    expect(bySeries.values.fold<int>(0, (a, b) => a + b.length), files);
    await measure('continueWatching', r.n, r.repo.continueWatching);
    await measure('upNextBySeries', r.n, r.repo.upNextBySeries);
    await measure('unmatchedFiles', r.n, r.repo.unmatchedFiles);
    await measure('allHiddenEpisodes', r.n, r.repo.allHiddenEpisodes);
    final one = await measure(
      'episodesFor(one show)',
      r.n,
      () => r.repo.episodesFor(300),
    );
    expect(one, isNotEmpty);
    await measure(
      'nextEpisode(one episode)',
      r.n,
      () => r.repo.nextEpisode(one.first),
    );
    await measure('library _reload equivalent (5 reads)', r.n, () async {
      await r.repo.allSeries();
      await r.repo.continueWatching();
      await r.repo.upNextBySeries();
      await r.repo.unmatchedFiles();
      await r.repo.episodesBySeries();
    });
    await measure(
      'applySync(empty) = one batch commit + prune',
      r.n,
      () => r.db.applySync(
        seriesUpserts: const [],
        fileUpserts: const [],
        removedKeys: const [],
      ),
    );
    await measure('saveProgress ×10 (the player tick)', r.n, () async {
      for (var i = 0; i < 10; i++) {
        await r.repo.saveProgress(
          one.first,
          position: Duration(seconds: i),
          duration: const Duration(minutes: 24),
        );
      }
    });
  });

  test(
    'episodesBySeries while every show is still pending (first scan)',
    () async {
      final r = await build(pendingFraction: 1);
      addTearDown(r.db.close);
      final placeholders = await measure(
        'episodesBySeries (P=600, first scan)',
        r.n,
        r.repo.episodesBySeries,
      );
      expect(placeholders.keys.every((id) => id < 0), isTrue);
      await measure('allSeries (P=600)', r.n, r.repo.allSeries);
    },
  );

  test('half pending, half identified (a scan mid-way)', () async {
    final r = await build(pendingFraction: 0.5);
    addTearDown(r.db.close);
    await measure('episodesBySeries (P=300)', r.n, r.repo.episodesBySeries);
  });

  test('a binge: 12 auto-advances', () async {
    final r = await build();
    addTearDown(r.db.close);
    var current = (await r.repo.episodesFor(300)).first;
    await measure('12 × (nextEpisode + episodesFor)', r.n, () async {
      for (var i = 0; i < 12; i++) {
        final next = await r.repo.nextEpisode(current);
        await r.repo.episodesFor(300);
        if (next is! NextEpisode) break;
        current = next.episode;
      }
    });
  });
}
