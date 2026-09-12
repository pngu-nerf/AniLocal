import 'package:anilocal/domain/models/skip_mode.dart';
import 'package:anilocal/domain/models/source_preference.dart';

import 'fake_settings.dart';

/// [FakeSettings] that RECORDS what reached the repository, so a test can
/// assert on the write and only the write. Reads still come from the
/// production defaults, except the two a panel reads back after writing —
/// the metadata source order and per-source client IDs — which round-trip
/// through [metadataOrder] / [clientIds] so the UI derives from the STORED
/// value, not a snapshot.
///
/// Every write also lands in [writes] as a `key=value` line, in order.
class RecorderSettings extends FakeSettings {
  RecorderSettings({this.metadataOrder = const [], this.clientIds = const {}});

  /// Every write, in order, as `key=value`.
  final List<String> writes = [];

  /// The persisted metadata source order — what `setMetadataSourceOrder` wrote.
  List<SourcePreference> metadataOrder;

  /// Per-source client IDs — what `setSourceClientId` wrote.
  Map<String, String?> clientIds;

  @override
  Future<void> setAutoPlayNext(bool enabled) async =>
      writes.add('autoPlayNext=$enabled');
  @override
  Future<void> setSkipMode(SkipMode mode) async =>
      writes.add('skip=${mode.name}');
  @override
  Future<void> setMissingEnabled(bool enabled) async =>
      writes.add('missing=$enabled');
  @override
  Future<void> setHideNextEpisode(bool hidden) async =>
      writes.add('hideNext=$hidden');
  @override
  Future<void> setShowContinueWatching(bool show) async =>
      writes.add('continue=$show');
  @override
  Future<void> setShowSearchBar(bool show) async => writes.add('search=$show');
  @override
  Future<void> setWatchedThreshold(Duration v) async =>
      writes.add('threshold=${v.inSeconds}');

  @override
  Future<List<SourcePreference>> loadMetadataSourceOrder() async =>
      metadataOrder;
  @override
  Future<void> setMetadataSourceOrder(List<SourcePreference> order) async {
    metadataOrder = order;
    writes.add(
      'metadataOrder=${[for (final p in order) '${p.token}:${p.enabled}'].join(',')}',
    );
  }

  @override
  Future<String?> loadSourceClientId(String token) async => clientIds[token];
  @override
  Future<void> setSourceClientId(String token, String? clientId) async {
    clientIds = {...clientIds, token: clientId};
    writes.add('clientId[$token]=$clientId');
  }
}
