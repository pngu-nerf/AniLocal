import 'dart:async';
import 'dart:io';

import 'package:anilocal/data/cache/art_cache.dart';
import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/metadata/metadata_provider.dart';
import 'package:anilocal/data/scanner/folder_scanner.dart';
import 'package:anilocal/data/scanner/heuristic_filename_parser.dart';
import 'package:anilocal/data/scanner/series_matcher.dart';
import 'package:anilocal/domain/models/external_ids.dart';
import 'package:anilocal/domain/models/series.dart';
import 'package:anilocal/domain/models/sync_control.dart';
import 'package:anilocal/domain/models/titles.dart';
import 'package:anilocal/sync/library_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A provider that answers every title with a distinct show and lets the test
/// act between lookups — cancel, count, or watch what has been committed.
class _ScriptedProvider implements MetadataProvider {
  _ScriptedProvider({this.onSearch});

  final Future<void> Function(int nth)? onSearch;
  int searches = 0;

  @override
  String get token => 'scripted';
  @override
  String get displayName => token;
  @override
  String get idNamespace => 'anilist';
  @override
  bool get isFallbackOnly => false;
  @override
  bool get requiresClientId => false;
  @override
  String? get setupUrl => null;
  @override
  String? get setupInstructions => null;
  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<List<Series>> searchCandidates(
    String title, {
    int perPage = 10,
  }) async {
    searches++;
    await onSearch?.call(searches);
    final id = 1000 + title.hashCode.abs() % 100000;
    return [
      Series(
        seriesId: id,
        externalIds: ExternalIds(anilist: id),
        titles: Titles(romaji: title),
      ),
    ];
  }

  @override
  Future<List<Series>> fetchByProviderIds(List<int> providerIds) async =>
      const [];
}

/// The scan's control flow: committed in batches, cancellable at every
/// checkpoint, one run at a time, progress after each commit. Before this the
/// scan was one 380-line method that wrote everything at the very end, could
/// not be stopped, and could be started twice over one database.
void main() {
  group('LibrarySync control flow', () {
    late Directory dir;
    late CacheDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anilocal_ctl_');
      db = CacheDatabase(NativeDatabase.memory());
      for (var i = 1; i <= 6; i++) {
        await File('${dir.path}/Show $i - 01.mkv').writeAsString('x');
      }
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    LibrarySync build(_ScriptedProvider provider, {int batchSize = 2}) =>
        LibrarySync(
          scanner: const FileSystemFolderScanner(),
          parser: const HeuristicFilenameParser(),
          matcher: SeriesMatcher(providers: [provider]),
          cache: db,
          art: ArtCache(
            httpClient: MockClient(
              (_) async => http.Response.bytes([1, 2, 3], 200),
            ),
            directory: () async => Directory('${dir.path}/.art')..createSync(),
          ),
          skipProviders: const [],
          batchSize: batchSize,
        );

    test('each batch is COMMITTED before the next starts', () async {
      final seenCommitted = <int, int>{}; // nth lookup -> matched rows so far
      late _ScriptedProvider provider;
      provider = _ScriptedProvider(
        onSearch: (nth) async {
          seenCommitted[nth] = (await db.allFileRows())
              .where((f) => f.seriesId != null)
              .length;
        },
      );
      await build(provider, batchSize: 2).sync([dir.path]);

      // Six titles, batches of two: lookups 3 and 5 start after one and two
      // batches have been written respectively.
      expect(seenCommitted[1], 0);
      expect(
        seenCommitted[3],
        2,
        reason: 'batch 1 on disk before batch 2 runs',
      );
      expect(
        seenCommitted[5],
        4,
        reason: 'batch 2 on disk before batch 3 runs',
      );
    });

    test(
      'cancelling keeps what was committed and leaves the rest pending',
      () async {
        final cancellation = SyncCancellation();
        final provider = _ScriptedProvider(
          onSearch: (nth) async {
            if (nth == 3) cancellation.cancel(); // mid-way through batch 2
          },
        );
        final summary = await build(
          provider,
          batchSize: 2,
        ).sync([dir.path], cancellation: cancellation);

        expect(summary.cancelled, isTrue);
        expect(summary.matched, 2, reason: 'exactly the first committed batch');
        expect(summary.removed, 0, reason: 'a cancelled run removes nothing');
        final rows = await db.allFileRows();
        expect(rows.where((f) => f.seriesId != null).length, 2);
        expect(
          rows.where((f) => f.pendingIdentification).length,
          4,
          reason:
              'the rest are the placeholders phase 1 wrote — retried next scan',
        );
        expect(
          provider.searches,
          3,
          reason: 'stopped at the checkpoint after it',
        );
      },
    );

    test('progress is reported after each committed batch', () async {
      final progress = <String>[];
      await build(
        _ScriptedProvider(),
        batchSize: 4,
      ).sync([dir.path], onProgress: (p) => progress.add('$p'));
      expect(progress, ['identifying 4/6', 'identifying 6/6']);
    });

    test('a second run while one is in flight is refused loudly', () async {
      final gate = Completer<void>();
      final provider = _ScriptedProvider(onSearch: (_) => gate.future);
      final sync = build(provider);
      final first = sync.sync([dir.path]);
      await Future<void>.delayed(
        Duration.zero,
      ); // let it reach the first lookup
      expect(sync.isRunning, isTrue);
      await expectLater(
        sync.refreshMetadata(),
        throwsA(isA<SyncAlreadyRunning>()),
      );
      gate.complete();
      await first;
      expect(sync.isRunning, isFalse);
    });
  });
}
