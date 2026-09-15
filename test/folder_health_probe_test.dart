import 'dart:io';

import 'package:anilocal/data/folders/folder_access.dart';
import 'package:anilocal/data/folders/folder_health_probe.dart';
import 'package:anilocal/data/folders/tcc_folder_access.dart';
import 'package:anilocal/data/folders/volume_resolver.dart';
import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/sync_summary.dart';
import 'package:anilocal/ui/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_folder_access.dart';
import 'support/fake_volume_resolver.dart';

/// Folder health after a drive is unplugged MID-SESSION. The launch pass
/// always got it right; the scan-time pass judged the unplugged folder
/// healthy because two caches kept positive answers for the life of the
/// process, and the label lists were mutated one folder at a time while the
/// path set was rebuilt — so the banner and the greying disagreed.
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('anilocal_health_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('DiskutilVolumeResolver', () {
    String plistFor(String mount) =>
        '<key>VolumeUUID</key><string>VOL</string>'
        '<key>MountPoint</key><string>$mount</string>';

    test(
      'a cached mount that no longer exists is re-asked, not trusted',
      () async {
        final mount = await Directory('${tmp.path}/Drive').create();
        var asks = 0;
        var answer = plistFor(mount.path);
        final resolver = DiskutilVolumeResolver(
          plist: (_) async {
            asks++;
            return answer;
          },
        );
        expect(await resolver.mountPointForVolumeId('VOL'), mount.path);
        expect(await resolver.mountPointForVolumeId('VOL'), mount.path);
        expect(asks, 1, reason: 'a present mount is served from the cache');

        await mount.delete(); // the drive is pulled
        answer =
            '<key>VolumeUUID</key><string>VOL</string>'
            '<key>MountPoint</key><string></string>';
        expect(await resolver.mountPointForVolumeId('VOL'), isNull);
        expect(asks, 2, reason: 'the stale positive answer was not believed');
      },
    );
  });

  group('TccFolderAccess', () {
    test('a confirmed volume root that vanished reports missing', () async {
      // Category roots are derived from the path shape, and a temp path can
      // only take the HOME rule (`<home>/Downloads`), so the volume rule is
      // exercised through the same code path with a home directory the test
      // controls.
      final access = TccFolderAccess(home: '${tmp.path}/home');
      final downloads = await Directory(
        '${tmp.path}/home/Downloads',
      ).create(recursive: true);
      final first = await access.ensureAccess('${downloads.path}/Anime');
      expect(first.state, FolderAccessState.accessible);
      final again = await access.ensureAccess('${downloads.path}/Anime');
      expect(again.state, FolderAccessState.accessible, reason: 'cached');

      await downloads.delete(recursive: true); // the root is gone
      final gone = await access.ensureAccess('${downloads.path}/Anime');
      expect(
        gone.state,
        FolderAccessState.missing,
        reason: '"granted" must mean readable NOW, not once',
      );
    });
  });

  group('FolderHealthProbe', () {
    FolderRef ref(String path, {String? volume, String? sub}) =>
        (path: path, volumeId: volume, volumeSubpath: sub);

    test(
      'rebuilds all three sets together; denied means unreadable now',
      () async {
        final present = await Directory('${tmp.path}/present').create();
        // Real directories, so the stored-path fast path finds them and only the
        // ACCESS verdict decides; the NAS folder has no directory and an
        // unmounted volume, so it resolves to nothing.
        final downloads = '${tmp.path}/Downloads';
        final anime = await Directory(
          '$downloads/Anime',
        ).create(recursive: true);
        final locked = await Directory('$downloads/Locked').create();
        final resolver = FakeVolumeResolver(); // 'GONE' is not mounted
        final access = FakeFolderAccess()
          ..byPrefix['/Volumes/NAS'] = const FolderAccessResult.missing(
            'the volume “NAS”',
          )
          ..byPrefix[downloads] = const FolderAccessResult.denied('Downloads');
        final unreadable = <String>{locked.path};
        final probe = FolderHealthProbe(
          resolver: resolver,
          access: access,
          readable: (p) async => !unreadable.contains(p),
        );
        final report = await probe.probe([
          ref(present.path),
          ref('/Volumes/NAS/Anime', volume: 'GONE', sub: 'Anime'),
          ref(anime.path), // denied grant, folder itself readable
          ref(locked.path), // denied grant AND unreadable
        ]);
        expect(report.missingPaths, {'/Volumes/NAS/Anime'});
        expect(report.missingLabels, ['the volume “NAS”']);
        expect(report.deniedLabels, [
          'Downloads',
        ], reason: 'raised by the unreadable folder only');

        // A readable Downloads folder alone raises nothing: the grant being
        // denied is not the user's problem while the folder reads.
        final quiet = await probe.probe([ref(anime.path)]);
        expect(quiet.deniedLabels, isEmpty);
        expect(quiet.missingPaths, isEmpty);
      },
    );

    test(
      'a folder whose probe throws is missing; the pass completes',
      () async {
        final access = FakeFolderAccess();
        final resolver = _ThrowingResolver();
        final probe = FolderHealthProbe(resolver: resolver, access: access);
        final report = await probe.probe([
          ref('/nowhere/a', volume: 'BOOM', sub: 'a'),
          ref('/nowhere/b', volume: 'BOOM', sub: 'b'),
        ]);
        expect(report.missingPaths, {'/nowhere/a', '/nowhere/b'});
      },
    );
  });

  group('the scan snackbar', () {
    const base = SyncSummary(
      filesScanned: 3,
      unchanged: 3,
      processed: 0,
      removed: 0,
      matched: 0,
      unmatched: 0,
      errored: 0,
    );
    test('is one message; red only when there is a problem line', () {
      final ok = scanResultText(base, (t) => t, missing: const {});
      expect(ok.problem, isFalse);
      expect(ok.text.split('\n'), hasLength(1));

      final bad = scanResultText(
        SyncSummary(
          filesScanned: 3,
          unchanged: 3,
          processed: 0,
          removed: 0,
          matched: 0,
          unmatched: 0,
          errored: 0,
          unreadableFolders: const ['/Volumes/NAS/Anime'],
          apiFailure: MetadataFailure.connection,
        ),
        (t) => t,
        missing: const {'/Volumes/NAS/Anime'},
      );
      expect(bad.problem, isTrue);
      final lines = bad.text.split('\n');
      expect(lines, hasLength(3));
      expect(lines[1], contains('not connected'));
      expect(lines[2], contains('kept as-is'));
    });
  });
}

class _ThrowingResolver implements VolumeResolver {
  @override
  Future<VolumeInfo?> infoForPath(String path) async => null;
  @override
  Future<String?> mountPointForVolumeId(String volumeId) =>
      throw const FileSystemException('wedged');
}
