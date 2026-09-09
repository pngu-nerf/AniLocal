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
const String kAniLocalUserAgent = 'AniLocal/1.0';
