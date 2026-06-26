import Cocoa
import FlutterMacOS
import MediaPlayer

class MainFlutterWindow: NSWindow {
  // Strong ref so the media-remote bridge lives as long as the window.
  private var mediaRemote: MediaRemoteHandler?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // System media-remote integration (AirPods pinch / keyboard play-pause key
    // / Bluetooth AVRCP). macOS only delivers these to the active now-playing
    // app, so this also claims now-playing status — see MediaRemoteHandler.
    mediaRemote = MediaRemoteHandler(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Bridges macOS system media-remote events to Flutter and claims now-playing
/// status. Lives in the runner (not a pub plugin) — `MediaPlayer` is a system
/// framework, so this adds no build-time download and no new dependency.
///
/// Two halves, both required: macOS routes remote events ONLY to the active
/// now-playing source, so registering command handlers without also feeding
/// `MPNowPlayingInfoCenter` would never receive an event.
///   • native → Dart: `MPRemoteCommandCenter` play / pause / togglePlayPause /
///     nextTrack are forwarded over the method channel; Dart routes them to the
///     existing player paths (no play/pause logic lives here).
///   • Dart → native: `updateNowPlaying` keeps title / duration / elapsed /
///     rate current so the OS picks this app as the source.
final class MediaRemoteHandler: NSObject {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "anilocal/media_remote", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    registerCommands()
  }

  // MARK: Dart -> native (now-playing state)

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateNowPlaying":
      updateNowPlaying(call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "clear":
      clearNowPlaying()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func updateNowPlaying(_ args: [String: Any]) {
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [String: Any]()

    if let title = args["title"] as? String {
      info[MPMediaItemPropertyTitle] = title
    }
    if let durationMs = args["durationMs"] as? Int {
      info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
    }
    if let positionMs = args["positionMs"] as? Int {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
        Double(positionMs) / 1000.0
    }
    let playing = (args["playing"] as? Bool) ?? false
    // Rate drives the system's elapsed-time extrapolation between updates.
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0

    center.nowPlayingInfo = info
    center.playbackState = playing ? .playing : .paused
  }

  private func clearNowPlaying() {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
  }

  // MARK: native -> Dart (remote commands)

  private func registerCommands() {
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    center.playCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("play", arguments: nil)
      return .success
    }
    center.pauseCommand.isEnabled = true
    center.pauseCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("pause", arguments: nil)
      return .success
    }
    // AirPods pinch and the keyboard play/pause key send toggle.
    center.togglePlayPauseCommand.isEnabled = true
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("togglePlayPause", arguments: nil)
      return .success
    }
    center.nextTrackCommand.isEnabled = true
    center.nextTrackCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("next", arguments: nil)
      return .success
    }
  }
}
