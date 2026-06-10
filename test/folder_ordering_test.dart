import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/drift_library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library folders keep a controllable order, not alphabetical', () async {
    final db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftLibraryRepository(db);

    // Added out of alphabetical order on purpose.
    await repo.addFolder('/Volumes/Zebra');
    await repo.addFolder('/Volumes/Apple');
    await repo.addFolder('/Volumes/Mango');

    final folders = await repo.watchedFolders();

    // Insertion order preserved (a rank), NOT sorted by path — so a later
    // feature can express "A ranks above B" without a migration.
    expect(folders.map((f) => f.path), [
      '/Volumes/Zebra',
      '/Volumes/Apple',
      '/Volumes/Mango',
    ]);
  });
}
