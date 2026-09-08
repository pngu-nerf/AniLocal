import 'package:equatable/equatable.dart';

/// Provider tokens. These are the SAME strings stored in
/// `series_external_ids.provider`, so the vocabulary lives here once rather
/// than being spelled out at each call site.
const String kAnilistProvider = 'anilist';
const String kMalProvider = 'mal';
const String kKitsuProvider = 'kitsu';
const String kAnidbProvider = 'anidb';

/// The ids other databases know a show by.
///
/// Deliberately NOT the show's identity — that is `series_id`, AniLocal's own
/// surrogate (see `series_identity.dart`). These are attributes, and any of
/// them may be absent: a show Kitsu knows and AniList doesn't has no
/// [anilist] id at all.
///
/// Carried on [Series] so a provider can report everything it knows in one
/// value, which is what lets `ensureSeriesId` recognise a show by ANY of its
/// ids rather than only the answering provider's — the thing that stops the
/// same show being minted twice under two identities.
class ExternalIds extends Equatable {
  const ExternalIds({this.anilist, this.mal, this.kitsu, this.anidb});

  /// Nothing known — a pending placeholder, or a provider that reported no ids.
  static const ExternalIds empty = ExternalIds();

  final int? anilist;
  final int? mal;
  final int? kitsu;
  final int? anidb;

  bool get isEmpty =>
      anilist == null && mal == null && kitsu == null && anidb == null;

  bool get isNotEmpty => !isEmpty;

  /// Only the ids actually present, keyed by provider token — the shape the
  /// `series_external_ids` rows take.
  Map<String, int> get byProvider => {
    kAnilistProvider: ?anilist,
    kMalProvider: ?mal,
    kKitsuProvider: ?kitsu,
    kAnidbProvider: ?anidb,
  };

  int? forProvider(String token) => byProvider[token];

  /// This value's ids, with any gaps filled from [other]. Used to accumulate
  /// what several sources know about one show WITHOUT letting a later source
  /// overwrite an id an earlier one already supplied.
  ExternalIds fillFrom(ExternalIds other) => ExternalIds(
    anilist: anilist ?? other.anilist,
    mal: mal ?? other.mal,
    kitsu: kitsu ?? other.kitsu,
    anidb: anidb ?? other.anidb,
  );

  /// Build from provider-token rows, ignoring tokens we don't model.
  factory ExternalIds.fromMap(Map<String, int> byProvider) => ExternalIds(
    anilist: byProvider[kAnilistProvider],
    mal: byProvider[kMalProvider],
    kitsu: byProvider[kKitsuProvider],
    anidb: byProvider[kAnidbProvider],
  );

  @override
  List<Object?> get props => [anilist, mal, kitsu, anidb];
}
