import Cocoa
import FlutterMacOS
import MediaPlayer

class MainFlutterWindow: NSWindow {
  // Strong ref so the media-remote bridge lives as long as the window.
  private var mediaRemote: MediaRemoteHandler?
  // Strong ref so the window-chrome channel keeps handling while the window lives.
  private var windowChannel: FlutterMethodChannel?
  // Borderless-fullscreen bookkeeping. We are the ONLY actor that changes
  // fullscreen state now, so these are authoritative rather than inferred.
  private var windowedFrame: NSRect?
  private var savedPresentationOptions: NSApplication.PresentationOptions?
  // Window chrome saved on the way in and put back on the way out. A normal
  // NSWindow keeps its shadow and its rounded corners at any size, so resizing
  // one to the screen still LOOKS like a window; native fullscreen used to strip
  // these for us. Saved rather than assumed so windowed mode can never be left
  // shadowless or square-cornered.
  private var savedCornerRadius: CGFloat?
  private var savedHasShadow: Bool?
  private var savedIsOpaque: Bool?
  private var savedBackgroundColor: NSColor?
  private var isBorderlessFullscreen = false
  /// Whether borderless fullscreen may be ENTERED right now. Dart sets this
  /// true only while the player is on screen — see the toggleFullScreen
  /// override for why entering anywhere else is a trap.
  private var fullscreenAllowed = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Spotify-style integrated title bar: hide the standard macOS title bar and
    // let the Flutter content span the FULL window height (into the former
    // title-bar region), so our own top bar becomes the real top of the window.
    // The traffic-light buttons stay in their DEFAULT top-left position and now
    // overlap our content — the Dart top bar indents its leading content past
    // them (see kTrafficLightInset). This is a static config set once (no button
    // repositioning, no observers), so native fullscreen enter/exit is unaffected.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // Minimum window size in LOGICAL POINTS (AppKit's coordinate space is
    // points, scaled by the display's backing factor — so this is identical on
    // Retina and non-Retina, unlike raw pixels). contentMinSize bounds the
    // content view; with the title bar hidden + fullSizeContentView the content
    // is the whole window, so the window can't be dragged smaller than this. The
    // layout is verified to stay usable (no overflow) at this size.
    self.contentMinSize = NSSize(width: 600, height: 400)

    // We removed the system title bar, so a click-drag on the system title bar
    // can no longer move the window. Restore move + zoom for a Dart-designated
    // drag region via NSWindow's own APIs — a system framework, so NO new
    // dependency and NO build-time download (same rationale as MediaRemote).
    let channel = FlutterMethodChannel(
      name: "anilocal/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startDrag":
        // performDrag runs its own modal move-loop from the in-flight mouse
        // event until mouse-up — the same technique window-manager plugins use.
        if let event = NSApp.currentEvent {
          self?.performDrag(with: event)
        }
        result(nil)
      case "toggleMaximize":
        self?.zoom(nil)
        result(nil)
      case "setFullscreen":
        self?.setBorderlessFullscreen((call.arguments as? Bool) ?? false)
        result(nil)
      case "setFullscreenAllowed":
        self?.setFullscreenAllowed((call.arguments as? Bool) ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowChannel = channel

    RegisterGeneratedPlugins(registry: flutterViewController)

    // System media-remote integration (AirPods pinch / keyboard play-pause key
    // / Bluetooth AVRCP). macOS only delivers these to the active now-playing
    // app, so this also claims now-playing status — see MediaRemoteHandler.
    mediaRemote = MediaRemoteHandler(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // MARK: - Borderless "presentation" fullscreen

  /// Fullscreen WITHOUT macOS's native fullscreen.
  ///
  /// `toggleFullScreen(_:)` moves the window into its own Space, and that Space
  /// switch is a fixed ~400ms system animation we cannot shorten — long enough
  /// that the window and our Dart layout visibly changed as two separate steps
  /// no matter which one we drove first. Borderless has no Space and no system
  /// transition: one `setFrame`, and Dart's repaint lands within a frame of it,
  /// so enter and exit are a single instant motion. This is the trade mpv and
  /// IINA make for the same reason — a player wants instant over Spaces.
  ///
  /// We are the ONLY actor that can change this state (there is no OS-initiated
  /// borderless fullscreen), so `isBorderlessFullscreen` is authoritative rather
  /// than inferred from delegate callbacks — which is why the whole
  /// NSWindowDelegate that used to observe native transitions is gone.
  ///
  /// Dart is still told through the SAME `fullscreenChanged` message as before,
  /// so `WindowChrome.fullscreen` remains the single source of truth and paths
  /// that don't go through the ⛶ button — notably Cmd-Ctrl-F, see
  /// `toggleFullScreen` below — stay in sync for free.
  func setBorderlessFullscreen(_ on: Bool) {
    guard on != isBorderlessFullscreen else { return }
    isBorderlessFullscreen = on

    if on {
      windowedFrame = frame
      savedPresentationOptions = NSApp.presentationOptions
      savedHasShadow = hasShadow
      savedIsOpaque = isOpaque
      savedBackgroundColor = backgroundColor

      // hideMenuBar REQUIRES hideDock (AppKit rejects it alone).
      NSApp.presentationOptions = [.hideDock, .hideMenuBar]
      // Hide the buttons while the window is still `.titled` — the accessors
      // only exist on a titled window.
      setTrafficLightsHidden(true)

      // ATTEMPT to square the corners — WITHOUT touching the style mask.
      //
      // ⚠️⚠️ KNOWN, ACCEPTED LIMITATION: THIS IS A NO-OP ON CURRENT macOS.
      // It runs, it is harmless, and the fullscreen window STILL HAS ROUNDED
      // CORNERS — the desktop peeks through four small corner arcs. That is a
      // deliberately accepted cosmetic quirk, not an open bug. Everything else
      // about fullscreen works: instant transition, first-press keyboard, cursor
      // wake, no shadow, full screen coverage.
      //
      // WHY WE ACCEPT IT — read this before "fixing" the corners. There are only
      // two ways to square them further, and both cost something real:
      //
      //   1. `styleMask = .borderless`. This DOES square them, and it was tried
      //      and reverted. Assigning the style mask rebuilds the window's frame
      //      view; the window does not re-acquire key status; a non-key window
      //      delivers neither key events nor mouseMoved to Flutter. Result: the
      //      first Escape is swallowed and the hidden cursor cannot be woken by
      //      moving the mouse. This regression bit us TWICE. `canBecomeKey` does
      //      not prevent it — that grants eligibility, not key status.
      //   2. Oversizing the window past the screen so the rounded corners fall
      //      off-screen. This crops the video and pushes the bottom of the
      //      control bar out of view.
      //
      // A minor cosmetic quirk beats dead keyboard + cursor input, and beats
      // cropping the picture. Rounded corners are the chosen lesser evil.
      // **DO NOT reach for `.borderless` to fix this** without re-reading the
      // above — it is the obvious-looking fix, and it is the one that broke
      // input. The style mask is never touched anywhere in this toggle.
      //
      // The call below is kept rather than deleted because it is free, it is the
      // correct shape if Apple's hierarchy ever makes it effective again, and
      // deleting it would lose this explanation.
      //
      // ⚠️ UNSUPPORTED API. `contentView?.superview` is AppKit's private
      // NSThemeFrame. Zeroing its layer's corner radius cannot disturb key
      // status, the first responder, or tracking areas — which is the whole
      // reason this shape was chosen over the style mask. On this macOS the
      // rounding evidently comes from somewhere this does not reach (a mask
      // layer, or the window server), hence the no-op.
      //
      // `wantsLayer` is deliberately NOT forced: if there is no layer, this
      // no-ops rather than changing how the window is backed.
      if let frameLayer = contentView?.superview?.layer {
        savedCornerRadius = frameLayer.cornerRadius
        frameLayer.cornerRadius = 0
      }
      // KILL THE EDGE SHEEN. Window shadows are independent of the style mask,
      // so a borderless window still casts one around the screen edge.
      hasShadow = false
      // Opaque black backing, so if anything ever fails to cover a pixel at the
      // edge it reads as letterboxing rather than as the desktop.
      isOpaque = true
      backgroundColor = .black

      // `frame`, not `visibleFrame`: with the menu bar hidden the whole screen
      // is ours. A single instant setFrame — no animator, no animation group.
      setFrame(screen?.frame ?? NSScreen.main?.frame ?? frame, display: true)
    } else {
      // Restore what was there before rather than assuming defaults, so we can
      // never strand the menu bar hidden, the window shadowless, or the corners
      // squared. The window stayed `.titled` throughout, so there is no frame
      // view to rebuild and no titlebar config to re-assert — which is exactly
      // why keyboard and cursor survive the toggle now.
      NSApp.presentationOptions = savedPresentationOptions ?? []
      if let radius = savedCornerRadius,
        let frameLayer = contentView?.superview?.layer
      {
        frameLayer.cornerRadius = radius
      }
      if let shadow = savedHasShadow { hasShadow = shadow }
      if let opaque = savedIsOpaque { isOpaque = opaque }
      if let colour = savedBackgroundColor { backgroundColor = colour }
      setTrafficLightsHidden(false)
      if let restored = windowedFrame {
        setFrame(restored, display: true)
      }

      savedPresentationOptions = nil
      savedCornerRadius = nil
      savedHasShadow = nil
      savedIsOpaque = nil
      savedBackgroundColor = nil
    }

    windowChannel?.invokeMethod("fullscreenChanged", arguments: on)
  }

  /// The traffic lights float over our content (we hid the title bar but kept
  /// the buttons), so unlike native fullscreen — where AppKit hides them for us
  /// — borderless has to hide them itself or they sit on top of the video.
  private func setTrafficLightsHidden(_ hidden: Bool) {
    standardWindowButton(.closeButton)?.isHidden = hidden
    standardWindowButton(.miniaturizeButton)?.isHidden = hidden
    standardWindowButton(.zoomButton)?.isHidden = hidden
  }

  /// Intercept EVERY route into AppKit's native fullscreen and redirect it to
  /// ours. `super` is deliberately never called.
  ///
  /// This one override covers the green button, Cmd-Ctrl-F and the View ▸ Enter
  /// Full Screen menu item — all of which call `toggleFullScreen(_:)`. Without
  /// it the system would drop the window into a native fullscreen Space behind
  /// our back, with our Dart state none the wiser.
  ///
  /// **Entering is SCOPED to the player; exiting never is.** Borderless
  /// fullscreen hides the header AND the traffic lights, which is right in the
  /// player (⛶ and Escape are both there) and a TRAP anywhere else: on a
  /// browsing page there would be no ⛶, no player shortcuts and no traffic
  /// lights, so nothing left to click. Rather than disable the green button
  /// globally, the fix is that fullscreen simply does not ENGAGE where it has
  /// no exit — outside the player the green button does the ordinary macOS
  /// thing (zoom) and the window stays windowed with its buttons intact.
  ///
  /// Exit is deliberately unconditional and checked FIRST, so no state and no
  /// ordering can ever make the window impossible to leave.
  override func toggleFullScreen(_ sender: Any?) {
    if isBorderlessFullscreen {
      setBorderlessFullscreen(false)
      return
    }
    guard fullscreenAllowed else {
      // Standard behaviour where standard behaviour is expected.
      zoom(sender)
      return
    }
    setBorderlessFullscreen(true)
  }

  /// Dart tells us when a fullscreen-capable surface (the player) is on screen.
  ///
  /// Turning permission OFF while fullscreen is active EXITS immediately. That
  /// enforces the invariant structurally rather than asking every caller to
  /// remember it: if the player goes away — popped, replaced, anything — the
  /// window cannot be left fullscreen with no way out.
  func setFullscreenAllowed(_ allowed: Bool) {
    fullscreenAllowed = allowed
    if !allowed && isBorderlessFullscreen {
      setBorderlessFullscreen(false)
    }
  }

  // Belt-and-braces, no longer load-bearing. These were added when fullscreen
  // assigned `.borderless` (such a window is not key-eligible unless the
  // subclass says so). That approach is gone — the window stays `.titled`, which
  // already answers true — so these now change nothing. Kept as cheap insurance
  // against any future change that makes the window non-titled: without them,
  // such a window silently stops accepting keyboard input.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
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
