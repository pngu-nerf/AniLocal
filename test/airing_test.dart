import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/domain/airing.dart';
import 'package:anilocal/domain/missing_episodes.dart';
import 'package:anilocal/domain/models/airing_status.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// The airing rule, pure, against a fixed clock. Every instant is stored;
/// "aired" and "in 3 days" are decided by the clock at render time.
void main() {
  final now = DateTime(2026, 9, 23, 20);
  Series show({
    AiringStatus status = AiringStatus.releasing,
    int? nextEpisode,
    DateTime? nextAt,
    int? count,
    DateTime? end,
    bool hidden = false,
  }) => Series(
    seriesId: 1,
    titles: const Titles(romaji: 'X'),
    airingStatus: status,
    nextAiringEpisode: nextEpisode,
    nextAiringAt: nextAt,
    episodeCount: count,
    endDate: end,
    airingHidden: hidden,
  );

  group('airedThroughFor', () {
    test('the episode before the scheduled one, until its time passes', () {
      final soon = show(
        nextEpisode: 9,
        nextAt: now.add(const Duration(days: 3)),
      );
      expect(airedThroughFor(soon, now), 8);
      final passed = show(
        nextEpisode: 9,
        nextAt: now.subtract(const Duration(hours: 1)),
      );
      expect(
        airedThroughFor(passed, now),
        9,
        reason: 'the clock says it is out',
      );
      expect(airedThroughFor(show(nextEpisode: 9, nextAt: now), now), 9);
    });
    test('no schedule → unknown; finished → the count; upcoming → none', () {
      expect(airedThroughFor(show(), now), isNull);
      expect(
        airedThroughFor(show(status: AiringStatus.finished, count: 12), now),
        12,
      );
      expect(
        airedThroughFor(show(status: AiringStatus.notYetReleased), now),
        0,
      );
      expect(airedThroughFor(show(status: AiringStatus.unknown), now), isNull);
    });
  });

  group('airingStateFor', () {
    test(
      'caught up → the quiet note with the next episode and its instant',
      () {
        final at = now.add(const Duration(days: 3));
        final s = airingStateFor(
          show(nextEpisode: 9, nextAt: at),
          highestPresent: 8,
          now: now,
        );
        expect(s, isA<Airing>());
        expect((s! as Airing).nextEpisode, 9);
        expect((s as Airing).nextAt, at);
      },
    );
    test(
      'an aired episode not in the library → the flag, with when it aired',
      () {
        final at = now.subtract(const Duration(days: 2));
        final s = airingStateFor(
          show(nextEpisode: 8, nextAt: at),
          highestPresent: 7,
          now: now,
        );
        expect(s, isA<NewEpisode>());
        expect((s! as NewEpisode).episode, 8);
        expect((s as NewEpisode).airedAt, at);
        // Two behind: the flag names the latest aired one, no air time claimed.
        final two = airingStateFor(
          show(nextEpisode: 9, nextAt: now.add(const Duration(days: 1))),
          highestPresent: 6,
          now: now,
        );
        expect((two! as NewEpisode).episode, 8);
        expect((two as NewEpisode).airedAt, isNull);
      },
    );
    test(
      'the scheduled episode aired and IS present: airing, next unknown until a scan',
      () {
        final s = airingStateFor(
          show(nextEpisode: 8, nextAt: now.subtract(const Duration(hours: 2))),
          highestPresent: 8,
          now: now,
        );
        expect(s, isA<Airing>());
        expect((s! as Airing).nextEpisode, isNull);
      },
    );
    test('no schedule (Kitsu, Jikan): the quiet note only', () {
      final s = airingStateFor(show(), highestPresent: 3, now: now);
      expect(s, isA<Airing>());
      expect((s! as Airing).nextEpisode, isNull);
    });
    test('finished: the flag for a week after the finale, then nothing', () {
      final finale = DateTime(2026, 9, 20);
      final fresh = show(status: AiringStatus.finished, count: 12, end: finale);
      expect(
        airingStateFor(fresh, highestPresent: 11, now: now),
        isA<NewEpisode>(),
      );
      expect(
        (airingStateFor(fresh, highestPresent: 11, now: now)! as NewEpisode)
            .episode,
        12,
      );
      expect(
        airingStateFor(fresh, highestPresent: 12, now: now),
        isNull,
        reason: 'downloaded',
      );
      final week = DateTime(2026, 9, 26, 12);
      expect(
        airingStateFor(fresh, highestPresent: 11, now: week),
        isA<NewEpisode>(),
        reason: 'inside the week',
      );
      final later = DateTime(2026, 9, 28);
      expect(
        airingStateFor(fresh, highestPresent: 11, now: later),
        isNull,
        reason: 'the week has passed',
      );
      expect(
        airingStateFor(
          show(status: AiringStatus.finished, count: 12),
          highestPresent: 1,
          now: now,
        ),
        isNull,
        reason: 'no finale date: nothing to measure',
      );
    });
    test('muted, upcoming or unknown → nothing', () {
      expect(
        airingStateFor(
          show(
            nextEpisode: 8,
            nextAt: now.subtract(const Duration(days: 1)),
            hidden: true,
          ),
          highestPresent: 0,
          now: now,
        ),
        isNull,
      );
      expect(
        airingStateFor(
          show(status: AiringStatus.notYetReleased),
          highestPresent: 0,
          now: now,
        ),
        isNull,
      );
      expect(
        airingStateFor(
          show(status: AiringStatus.unknown),
          highestPresent: 0,
          now: now,
        ),
        isNull,
      );
    });
  });

  group('the missing window while airing', () {
    Episode ep(int n) =>
        Episode(number: n, anchoredNumber: n, seriesId: 1, fileRef: 'f$n.mkv');
    test('ghosts stop at the last aired episode, not the season total', () {
      final slots = computeEpisodeSlots(
        present: [ep(1), ep(2)],
        hidden: const {},
        episodeCount: 12,
        airedThrough: 4,
      );
      expect(slots.map((s) => s.number), [1, 2, 3, 4]);
      final tally = computeDownloadTally(slots, 12, airedThrough: 4);
      expect(tally.total, 4);
      expect(tally.inRange, 2);
    });
    test(
      'unknown total: the aired count is the window; finished: unchanged',
      () {
        final slots = computeEpisodeSlots(
          present: [ep(1)],
          hidden: const {},
          episodeCount: null,
          airedThrough: 3,
        );
        expect(slots.map((s) => s.number), [1, 2, 3]);
        final full = computeEpisodeSlots(
          present: [ep(1)],
          hidden: const {},
          episodeCount: 3,
          airedThrough: null,
        );
        expect(full.map((s) => s.number), [1, 2, 3]);
        expect(
          knownEpisodeWindow(12, 20),
          12,
          reason: 'aired past the total: the total',
        );
      },
    );
  });

  group('needsAiringCheck (the scan phase filter)', () {
    final nowMs = now.millisecondsSinceEpoch;
    CachedSeriesRow row({
      String? status,
      int? checked,
      int? nextAt,
      String? end,
    }) => CachedSeriesRow(
      seriesId: 1,
      airingStatus: status,
      airingCheckedAtMs: checked,
      nextAiringAtMs: nextAt,
      endDate: end,
    );
    test('never asked → asked; asked recently → not', () {
      expect(LibrarySync.needsAiringCheck(row(), nowMs), isTrue);
      expect(
        LibrarySync.needsAiringCheck(
          row(status: 'releasing', checked: nowMs - 1000),
          nowMs,
        ),
        isFalse,
      );
      expect(
        LibrarySync.needsAiringCheck(
          row(
            status: 'releasing',
            checked: nowMs - kAiringRecheck.inMilliseconds - 1,
          ),
          nowMs,
        ),
        isTrue,
      );
    });
    test('a scheduled episode that has aired makes the row stale at once', () {
      expect(
        LibrarySync.needsAiringCheck(
          row(status: 'releasing', checked: nowMs - 1000, nextAt: nowMs - 1),
          nowMs,
        ),
        isTrue,
      );
      expect(
        LibrarySync.needsAiringCheck(
          row(status: 'releasing', checked: nowMs - 1000, nextAt: nowMs + 1),
          nowMs,
        ),
        isFalse,
      );
    });
    test('finished shows are asked only inside the week after the finale', () {
      final old = nowMs - kAiringRecheck.inMilliseconds - 1;
      expect(
        LibrarySync.needsAiringCheck(
          row(status: 'finished', checked: old, end: '2026-09-20'),
          nowMs,
        ),
        isTrue,
      );
      expect(
        LibrarySync.needsAiringCheck(
          row(status: 'finished', checked: old, end: '2026-01-01'),
          nowMs,
        ),
        isFalse,
      );
      expect(
        LibrarySync.needsAiringCheck(
          row(status: 'unknown', checked: old),
          nowMs,
        ),
        isFalse,
        reason: 'asked, and the source did not know: leave it',
      );
    });
  });
}
