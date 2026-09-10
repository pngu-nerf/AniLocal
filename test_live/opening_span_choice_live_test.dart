import 'dart:io';

import 'package:anilocal/data/aniskip/aniskip_client.dart';
import 'package:anilocal/data/chapters/chapter_reader.dart';
import 'package:anilocal/data/skip/aniskip_skip_provider.dart';
import 'package:anilocal/data/skip/skip_provider.dart';
import 'package:anilocal/domain/chapter_skips.dart';
import 'package:anilocal/domain/models/skip_range.dart';
import 'package:anilocal/domain/skip_corroboration.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settles ONE open question with data: when a file has more than one
/// theme-length chapter before its midpoint, is the EARLIEST the opening (what
/// `inferSkipsFromChapters` assumes today) or the LATEST?
///
///   flutter test test_live/opening_span_choice_live_test.dart
///
/// Why it exists. Corroboration on the reference library left nine windows
/// marked `conflicting`, and every one had the same shape: chapters said
/// `0 → ~90s` while AniSkip put the opening at `~90 → ~180s`, exactly where the
/// chapter window ended. That is a cold open of coincidentally theme-like
/// length being mistaken for the opening. Preferring the later span would fix
/// them — but the earliest-wins rule exists for a measured case (an episode
/// that opens cold with its OP at 498s while its neighbours start theirs at 0s),
/// so flipping it blind could trade nine known errors for an unknown number of
/// new ones.
///
/// AniSkip is the independent authority here, the same role ffprobe plays in
/// `chapter_reader_live_test.dart`. It is human-submitted and sometimes wrong
/// about the exact boundary, so this measures which candidate is CLOSER, using
/// the same overlap metric the corroboration rule uses — not whether either
/// matches exactly.
///
/// Reads the real cache to map each file to its series, episode and
/// MyAnimeList id, because that mapping is what the fill path uses and
/// re-deriving it here would measure something else. Via the `sqlite3` CLI
/// rather than a package — same reason this directory already shells out to
/// `ffprobe`, and it keeps a live-only harness from adding a dependency to the
/// shipped app. Read-only, against a COPY, so the running app's cache is never
/// touched.
///
/// Writes its findings to `build/opening_span_report.txt` (gitignored) so the
/// numbers survive the run and can be read without scrolling the log.
const String _root = '/Volumes/Anime';
const String _reportPath = 'build/opening_span_report.txt';

/// Every theme-length chapter span starting before the midpoint, in order.
/// This is deliberately the SAME band the production rule uses, so the two
/// cannot drift apart and make this measurement meaningless.
List<ChapterSpan> _candidatesBeforeMidpoint(
  List<ChapterMark> marks,
  Duration duration,
) {
  final midpoint = duration ~/ 2;
  return [
    for (final span in chapterSpans(marks, duration))
      if (span.start < midpoint &&
          span.length >= kOpeningMinLength &&
          span.length <= kOpeningMaxLength)
        span,
  ];
}

String _fmt(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(1);

void main() {
  test(
    'LIVE: earliest vs latest theme-length span before the midpoint',
    () async {
      final lines = <String>[];
      void log(String s) {
        lines.add(s);
        // ignore: avoid_print
        print(s);
      }

      if (!Directory(_root).existsSync()) {
        markTestSkipped('$_root is not mounted');
        return;
      }
      // Prove readability up front rather than reporting an empty library: TCC
      // denies reads on a removable volume per RESPONSIBLE PROCESS, and
      // ChapterReader turns any failure into "no chapters", so a permission
      // problem would otherwise look exactly like a library with no chapter marks.
      try {
        Directory(_root).listSync().take(1).toList();
      } on FileSystemException catch (e) {
        fail(
          'Cannot read $_root — ${e.osError?.message ?? e.message}.\n'
          'This is a macOS permission denial, not an absent library: grant the '
          'app hosting this shell access under Privacy & Security > Files and '
          'Folders > Removable Volumes.',
        );
      }

      final home = Platform.environment['HOME']!;
      final live = File(
        '$home/Library/Application Support/com.anilocal.anilocal/anilocal/cache.sqlite',
      );
      if (!live.existsSync()) {
        markTestSkipped('no cache at ${live.path} — run the app once first');
        return;
      }
      final copy = File(
        '${Directory.systemTemp.path}/anilocal_span_probe.sqlite',
      );
      live.copySync(copy.path);

      // One row per matched file, carrying the MAL id AniSkip is keyed by. Unit
      // separator rather than a comma: show titles contain commas.
      const sep = '\x1f';
      final query = Process.runSync('sqlite3', [
        '-readonly',
        '-noheader',
        '-separator',
        sep,
        copy.path,
        "SELECT f.folder_path || '/' || f.relative_path, f.episode_number, "
            "COALESCE(sc.romaji, sc.english, 'series ' || f.series_id), "
            'COALESCE(e.external_id, \'\') '
            'FROM file_cache f '
            'LEFT JOIN series_cache sc ON sc.series_id = f.series_id '
            "LEFT JOIN series_external_ids e ON e.series_id = f.series_id AND e.provider = 'mal' "
            'WHERE f.series_id IS NOT NULL AND f.episode_number IS NOT NULL '
            'ORDER BY 3, 2',
      ]);
      if (query.exitCode != 0) {
        fail('sqlite3 failed: ${query.stderr}');
      }
      final rows = [
        for (final line in (query.stdout as String).split('\n'))
          if (line.trim().isNotEmpty) line.split(sep),
      ];

      const reader = ChapterReader();
      final aniskip = AniSkipSkipProvider(AniSkipClient());

      var files = 0, withChapters = 0, noCandidate = 0, one = 0, several = 0;
      var earliestWins = 0, latestWins = 0, neitherClose = 0, noAniSkip = 0;
      final detail = <String>[];

      for (final row in rows) {
        final path = row[0];
        if (!File(path).existsSync()) continue;
        files++;
        final chapters = await reader.read(path);
        if (chapters.isEmpty) continue;
        withChapters++;

        final candidates = _candidatesBeforeMidpoint(
          chapters.marks,
          chapters.duration,
        );
        if (candidates.isEmpty) {
          noCandidate++;
          continue;
        }
        if (candidates.length == 1) {
          one++;
          continue;
        }
        several++;

        // Only the ambiguous files cost a request, which is why this is cheap.
        final ep = int.parse(row[1]);
        final show = row[2];
        final mal = int.tryParse(row[3]);
        final answer = mal == null
            ? null
            : await aniskip.fetchSkips(
                SkipLookup(seriesId: 0, episode: ep, malId: mal),
              );
        final truth = answer?.intro;
        if (truth == null) {
          noAniSkip++;
          detail.add(
            '  $show ep$ep — ${candidates.length} candidates, '
            'AniSkip has nothing to judge by',
          );
          continue;
        }

        final earliest = candidates.first;
        final latest = candidates.last;
        SkipRange asRange(ChapterSpan s) =>
            SkipRange(start: s.start, end: s.end);
        final oEarly = windowOverlap(asRange(earliest), truth);
        final oLate = windowOverlap(asRange(latest), truth);

        final String verdict;
        if (oEarly < kSkipCorroborationMinOverlap &&
            oLate < kSkipCorroborationMinOverlap) {
          neitherClose++;
          verdict = 'NEITHER';
        } else if (oLate > oEarly) {
          latestWins++;
          verdict = 'LATEST';
        } else {
          earliestWins++;
          verdict = 'earliest';
        }
        detail.add(
          '  $show ep$ep  $verdict  '
          'earliest ${_fmt(earliest.start)}→${_fmt(earliest.end)} '
          '(${(oEarly * 100).toStringAsFixed(0)}%)  '
          'latest ${_fmt(latest.start)}→${_fmt(latest.end)} '
          '(${(oLate * 100).toStringAsFixed(0)}%)  '
          'aniskip ${_fmt(truth.start)}→${_fmt(truth.end)}',
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      copy.deleteSync();

      log('=== files ===');
      log('  matched files present on disk : $files');
      log('  with readable chapters        : $withChapters');
      log('  no theme-length span at all   : $noCandidate');
      log('  exactly ONE candidate         : $one   (nothing to decide)');
      log('  TWO OR MORE candidates        : $several   (the whole question)');
      log('');
      log('=== of the ambiguous files, which candidate matches AniSkip? ===');
      log('  earliest (what we do today)   : $earliestWins');
      log('  LATEST                        : $latestWins');
      log('  neither is close              : $neitherClose');
      log('  AniSkip had no answer         : $noAniSkip');
      log('');
      log('=== detail ===');
      for (final d in detail) {
        log(d);
      }
      log('');
      log(
        'READ THIS AS: switching to latest-wins is justified only if LATEST '
        'clearly outnumbers earliest. If earliest wins even a handful, the rule '
        'is right as it stands and those nine windows stay a corroboration '
        'problem rather than an inference one.',
      );

      Directory('build').createSync(recursive: true);
      File(_reportPath).writeAsStringSync('${lines.join('\n')}\n');
      // ignore: avoid_print
      print('\nreport written to $_reportPath');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
