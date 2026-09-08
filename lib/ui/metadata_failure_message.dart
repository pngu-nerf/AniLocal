import '../domain/models/metadata_failure.dart';

/// The ONE place AniList-failure copy lives. Both the scan snackbar and the
/// refresh snackbar render from here, so the wording can't drift apart.
///
/// This returns only the CAUSE — whose end the fault is on and what the user
/// can do about it. Each call site appends its own consequence sentence, since
/// what was preserved differs (a scan keeps the library; a refresh keeps
/// metadata). Splitting it that way keeps the part that varies by failure kind
/// in a single switch.
String metadataFailureCause(MetadataFailure failure) => switch (failure) {
  MetadataFailure.connection =>
    "Couldn't reach AniList — check your internet connection.",
  MetadataFailure.blocked =>
    "Something on your network blocked the request to AniList — a VPN, proxy "
        'or Wi-Fi portal. AniList itself is fine.',
  MetadataFailure.service =>
    "AniList's API is down right now — nothing to fix on your end. "
        'Try again later.',
  MetadataFailure.rateLimited =>
    'AniList is rate-limiting us — wait a minute, then try again.',
};
