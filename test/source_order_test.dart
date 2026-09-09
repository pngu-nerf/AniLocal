import 'package:anilocal/domain/models/source_preference.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ordering rule is shared by the scan, fix-match and the settings list, so
/// it lives in one pure function. These pin the parts that only bite later:
/// what happens to a source the saved order has never heard of, and what
/// happens to one it names that no longer exists.
void main() {
  const available = ['anilist', 'kitsu', 'jikan'];
  String tokenOf(String s) => s;

  test('an empty preference list keeps the built-in order', () {
    // The first-run state. Nothing to seed, nothing to migrate.
    expect(applySourceOrder(available, tokenOf, const []), [
      'anilist',
      'kitsu',
      'jikan',
    ]);
  });

  test('the saved order wins', () {
    expect(
      applySourceOrder(available, tokenOf, const [
        SourcePreference(token: 'jikan'),
        SourcePreference(token: 'anilist'),
        SourcePreference(token: 'kitsu'),
      ]),
      ['jikan', 'anilist', 'kitsu'],
    );
  });

  test('a disabled source is dropped from the lookup chain', () {
    expect(
      applySourceOrder(available, tokenOf, const [
        SourcePreference(token: 'anilist', enabled: false),
        SourcePreference(token: 'kitsu'),
        SourcePreference(token: 'jikan'),
      ]),
      ['kitsu', 'jikan'],
    );
  });

  test('but the settings list still SEES a disabled source', () {
    // Otherwise there would be no way to switch it back on.
    expect(
      applySourceOrder(available, tokenOf, const [
        SourcePreference(token: 'anilist', enabled: false),
        SourcePreference(token: 'kitsu'),
        SourcePreference(token: 'jikan'),
      ], enabledOnly: false),
      ['anilist', 'kitsu', 'jikan'],
    );
  });

  test('a NEW source is enabled by default and appended', () {
    // The upgrade case: the user saved an order before this source shipped.
    // Defaulting it OFF would silently withhold a feature in every existing
    // install, and nothing would tell them why.
    expect(
      applySourceOrder(available, tokenOf, const [
        SourcePreference(token: 'kitsu'),
        SourcePreference(token: 'anilist'),
      ]),
      ['kitsu', 'anilist', 'jikan'],
    );
    expect(
      isSourceEnabled('jikan', const [SourcePreference(token: 'kitsu')]),
      isTrue,
    );
  });

  test('a preference for a source that no longer ships is ignored', () {
    // Saved order is user data and outlives any one release; a removed source
    // must not break the list or throw.
    expect(
      applySourceOrder(available, tokenOf, const [
        SourcePreference(token: 'anidb'), // gone
        SourcePreference(token: 'kitsu'),
      ]),
      ['kitsu', 'anilist', 'jikan'],
    );
  });

  test('order and enablement round-trip through isSourceEnabled', () {
    const prefs = [
      SourcePreference(token: 'anilist', enabled: false),
      SourcePreference(token: 'kitsu'),
    ];
    expect(isSourceEnabled('anilist', prefs), isFalse);
    expect(isSourceEnabled('kitsu', prefs), isTrue);
    expect(
      isSourceEnabled('unknown', prefs),
      isTrue,
      reason: 'unmentioned sources default on',
    );
  });
}
