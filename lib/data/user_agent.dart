/// How AniLocal identifies itself to every remote service.
///
/// Shared rather than per-module because it is one fact about this app, not
/// about any one source. It lived in the AniList client while that was the only
/// caller; AniSkip and the cross-map then imported it from there, which quietly
/// made `lib/data/anilist` a dependency of unrelated modules.
///
/// REQUIRED, not politeness: AniList sits behind Cloudflare, which 403s the
/// `http` package's default user agent. A stable, named UA gets through — and
/// is good public-API citizenship everywhere else.
///
/// Carries the REAL version and a contact URL, per the convention public APIs
/// expect of a named client. Three of the services this identifies to are
/// volunteer-run; if AniLocal ever misbehaves this is how they reach someone,
/// and the version is the only signal they get about WHICH build did it. It
/// used to be a hard-coded `AniLocal/1.0` disconnected from pubspec — which
/// would have lied the moment the version moved. Set once at startup from the
/// bundle; the placeholder covers the first milliseconds before that resolves.
String aniLocalUserAgent = 'AniLocal/unknown (+$kAniLocalProjectUrl)';

/// Where the source lives — also the GPL source-availability answer.
const String kAniLocalProjectUrl = 'https://github.com/pngu-nerf/AniLocal';

/// Build the UA for [version] (`1.0.0+2`).
String userAgentFor(String version) =>
    'AniLocal/$version (+$kAniLocalProjectUrl)';
