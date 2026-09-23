import 'package:anilocal/data/cache/cache_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The broadcast columns have their own write because the series upsert
/// cannot clear a value: null there means "keep", here it means "gone".
void main() {
  late CacheDatabase db;
  setUp(() => db = CacheDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'updateAiring writes every column, nulls included; upsertSeries leaves them alone',
    () async {
      await db.upsertSeries(const CachedSeriesRow(seriesId: 1, romaji: 'X'));
      await db.updateAiring(
        1,
        status: 'releasing',
        nextAiringAtMs: 5000,
        nextAiringEpisode: 5,
        endDate: null,
        checkedAtMs: 1,
      );
      var r = (await db.seriesRow(1))!;
      expect(
        (
          r.airingStatus,
          r.nextAiringAtMs,
          r.nextAiringEpisode,
          r.airingCheckedAtMs,
        ),
        ('releasing', 5000, 5, 1),
      );

      // A metadata refresh that knows nothing about airing must not wipe it.
      await db.upsertSeries(
        const CachedSeriesRow(seriesId: 1, romaji: 'X', english: 'Ex'),
      );
      r = (await db.seriesRow(1))!;
      expect(r.english, 'Ex');
      expect(r.nextAiringEpisode, 5, reason: 'no-wipe upsert');

      // The show finished: the next episode is GONE, and the row must say so.
      await db.updateAiring(
        1,
        status: 'finished',
        nextAiringAtMs: null,
        nextAiringEpisode: null,
        endDate: '2026-09-20',
        checkedAtMs: 2,
      );
      r = (await db.seriesRow(1))!;
      expect(r.airingStatus, 'finished');
      expect(r.nextAiringAtMs, isNull);
      expect(r.nextAiringEpisode, isNull);
      expect(r.endDate, '2026-09-20');
    },
  );

  test('the per-show mute is its own column with a default', () async {
    await db.setShowAiringHidden(7, hidden: true);
    expect((await db.showPrefFor(7))!.airingHidden, isTrue);
    expect((await db.showPrefFor(7))!.nextEpisodeHidden, isFalse);
    await db.setShowAiringHidden(7, hidden: false);
    expect((await db.showPrefFor(7))!.airingHidden, isFalse);
  });
}
