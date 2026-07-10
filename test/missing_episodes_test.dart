import 'package:anilocal/domain/missing_episodes.dart';
import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/domain/models/episode_list_row.dart';
import 'package:anilocal/domain/models/episode_slot.dart';
import 'package:flutter_test/flutter_test.dart';

/// A present episode anchored at [n].
Episode _ep(int n) => Episode(
  number: n,
  fileRef: 'f$n.mkv',
  seriesAnilistId: 1,
  anchoredNumber: n,
);

/// Convenience: the (number, status) shape of computed slots.
List<(int, EpisodeStatus)> _shape(List<EpisodeSlot> slots) => [
  for (final s in slots) (s.number, s.status),
];

void main() {
  group('computeEpisodeSlots', () {
    test('M known: absent positions in 1..M are missing', () {
      final slots = computeEpisodeSlots(
        present: [_ep(1), _ep(2), _ep(4)],
        hidden: const {},
        episodeCount: 5,
      );
      expect(_shape(slots), [
        (1, EpisodeStatus.present),
        (2, EpisodeStatus.present),
        (3, EpisodeStatus.missing),
        (4, EpisodeStatus.present),
        (5, EpisodeStatus.missing),
      ]);
    });

    test('M unknown: only INTERIOR gaps, never beyond the highest owned', () {
      final slots = computeEpisodeSlots(
        present: [_ep(3), _ep(5)],
        hidden: const {},
        episodeCount: null,
      );
      // 4 is an interior gap; nothing below 3 or above 5 is invented.
      expect(_shape(slots), [
        (3, EpisodeStatus.present),
        (4, EpisodeStatus.missing),
        (5, EpisodeStatus.present),
      ]);
    });

    test('M unknown, single owned episode: no phantom gaps', () {
      final slots = computeEpisodeSlots(
        present: [_ep(1)],
        hidden: const {},
        episodeCount: null,
      );
      expect(_shape(slots), [(1, EpisodeStatus.present)]);
    });

    test('specials (position <= 0) are present, never flagged missing', () {
      final slots = computeEpisodeSlots(
        present: [_ep(0), _ep(1), _ep(2)],
        hidden: const {},
        episodeCount: 2,
      );
      expect(_shape(slots), [
        (0, EpisodeStatus.present),
        (1, EpisodeStatus.present),
        (2, EpisodeStatus.present),
      ]);
    });

    test('present beyond M is kept (present), not gap-detected', () {
      final slots = computeEpisodeSlots(
        present: [_ep(1), _ep(2), _ep(3), _ep(5)],
        hidden: const {},
        episodeCount: 3,
      );
      // 4 is missing (in 1..3? no — 4 > 3, so NOT missing); 5 present, kept.
      expect(_shape(slots), [
        (1, EpisodeStatus.present),
        (2, EpisodeStatus.present),
        (3, EpisodeStatus.present),
        (5, EpisodeStatus.present),
      ]);
    });

    test('hidden positions become hidden slots (excluded from missing)', () {
      final slots = computeEpisodeSlots(
        present: [_ep(1), _ep(2), _ep(4)],
        hidden: const {3},
        episodeCount: 5,
      );
      expect(_shape(slots), [
        (1, EpisodeStatus.present),
        (2, EpisodeStatus.present),
        (3, EpisodeStatus.hidden),
        (4, EpisodeStatus.present),
        (5, EpisodeStatus.missing),
      ]);
    });
  });

  group('groupIntoRows', () {
    List<EpisodeListRow> rows(List<Episode> present, Set<int> hidden, int? m) =>
        groupIntoRows(
          computeEpisodeSlots(
            present: present,
            hidden: hidden,
            episodeCount: m,
          ),
        );

    test('a run of 2+ consecutive missing collapses to one bundle', () {
      final r = rows([_ep(1)], const {}, 10);
      expect(r[0], isA<PresentRow>());
      expect(r[1], isA<MissingBundleRow>());
      final bundle = r[1] as MissingBundleRow;
      expect(bundle.first, 2);
      expect(bundle.last, 10);
      expect(bundle.numbers, [2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(r.length, 2);
    });

    test('an isolated missing episode is a single, not a bundle', () {
      final r = rows([_ep(1), _ep(3)], const {}, 3);
      expect(r.map((x) => x.runtimeType).toList(), [
        PresentRow,
        MissingSingleRow,
        PresentRow,
      ]);
      expect((r[1] as MissingSingleRow).number, 2);
    });

    test('multiple runs and singles interleave in order', () {
      final r = rows([_ep(1), _ep(5), _ep(6), _ep(10)], const {}, 10);
      expect(r.map((x) => x.runtimeType).toList(), [
        PresentRow, // 1
        MissingBundleRow, // 2-4
        PresentRow, // 5
        PresentRow, // 6
        MissingBundleRow, // 7-9
        PresentRow, // 10
      ]);
      expect((r[1] as MissingBundleRow).numbers, [2, 3, 4]);
      expect((r[4] as MissingBundleRow).numbers, [7, 8, 9]);
    });

    test('hiding mid-run re-groups: a hidden gap splits a bundle', () {
      // Missing would be 2,3,4,5,6,7; hide 4 and 5 → two separate bundles.
      final r = rows([_ep(1), _ep(8)], const {4, 5}, 8);
      expect(r.map((x) => x.runtimeType).toList(), [
        PresentRow, // 1
        MissingBundleRow, // 2-3
        MissingBundleRow, // 6-7
        PresentRow, // 8
      ]);
      expect((r[1] as MissingBundleRow).numbers, [2, 3]);
      expect((r[2] as MissingBundleRow).numbers, [6, 7]);
    });

    test('a hidden single between missing yields two singles', () {
      // Missing 2,4,5; hide 3 → single 2, bundle 4-5.
      final r = rows([_ep(1), _ep(6)], const {3}, 6);
      expect(r.map((x) => x.runtimeType).toList(), [
        PresentRow, // 1
        MissingSingleRow, // 2
        MissingBundleRow, // 4-5
        PresentRow, // 6
      ]);
      expect((r[1] as MissingSingleRow).number, 2);
      expect((r[2] as MissingBundleRow).numbers, [4, 5]);
    });
  });

  group('computeDownloadTally', () {
    DownloadTally tally(List<Episode> present, Set<int> hidden, int? m) =>
        computeDownloadTally(
          computeEpisodeSlots(
            present: present,
            hidden: hidden,
            episodeCount: m,
          ),
          m,
        );

    test('counts in-range and out-of-range present episodes', () {
      final t = tally([_ep(1), _ep(2), _ep(3), _ep(5)], const {}, 3);
      expect(t.inRange, 3);
      expect(t.outOfRange, 1); // ep 5 beyond M=3
      expect(t.total, 3);
    });

    test('hidden in-range positions reduce the denominator', () {
      // Have 11 of 12, ep 12 missing → hide it → "11 of 11".
      final present = [for (var n = 1; n <= 11; n++) _ep(n)];
      final t = tally(present, const {12}, 12);
      expect(t.inRange, 11);
      expect(t.total, 11);
      expect(t.outOfRange, 0);
    });

    test('unknown M yields a null total (indicator shows just N)', () {
      final t = tally([_ep(1), _ep(2)], const {}, null);
      expect(t.inRange, 2);
      expect(t.total, isNull);
    });
  });
}
