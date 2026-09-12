import 'package:anilocal/data/cache/cache_database.dart';
import 'package:anilocal/data/cache/series_identity.dart';
import 'package:anilocal/domain/models/external_ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The minted-id counter lives in `app_settings`, a hand-editable store. If it
/// goes missing, restarting at the base would re-issue an id another show
/// already owns — a silent merge. The floor is what is already in use.
void main() {
  test('a missing counter never re-issues a minted id', () async {
    final db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final first = await db.ensureSeriesId(const ExternalIds(kitsu: 1));
    final second = await db.ensureSeriesId(const ExternalIds(kitsu: 2));
    expect(isMintedSeriesId(first), isTrue);
    expect(second, first + 1);

    await db.customStatement(
      "DELETE FROM app_settings WHERE key = 'next_minted_series_id'",
    );

    final third = await db.ensureSeriesId(const ExternalIds(kitsu: 3));
    expect(third, greaterThan(second), reason: 'seeded from what exists');
    expect({first, second, third}, hasLength(3));
  });
}
