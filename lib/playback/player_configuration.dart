import 'package:media_kit/media_kit.dart';

/// The ONE libmpv configuration the app builds its player with.
///
/// media_kit's defaults are right for this app today — `vo=null` with the
/// texture rendered by `media_kit_video`, mpv's own libass subtitle rendering,
/// a 32 MB demuxer buffer — so nothing is overridden except what makes the
/// engine observable:
///
/// - [PlayerConfiguration.logLevel] at `warn`, so mpv's warnings and errors
///   reach `Player.stream.log` (the composition root forwards them to the
///   diagnostics ring). At the default `error` a failing decoder or a missing
///   codec left nothing behind for "Copy diagnostics" to carry.
/// - [PlayerConfiguration.title] names the mpv instance for tooling.
///
/// This is also where a future hardware-decoding preference, cache tuning, or
/// the Anime4K shader path (a deferred feature) would be set — one declared
/// place, not a property poked at the player after the fact.
const PlayerConfiguration kPlayerConfiguration = PlayerConfiguration(
  title: 'AniLocal',
  logLevel: MPVLogLevel.warn,
);
