import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Left inset (logical px) reserved at the top-left of every top bar so the
/// macOS traffic-light buttons never overlap our controls.
///
/// We hid the standard title bar (Spotify-style — see `MainFlutterWindow.swift`)
/// but deliberately leave the close/minimize/fullscreen buttons in their default
/// position; they now float over the top-left of our content. This is the
/// footprint of those three buttons plus a little breathing room, so our leading
/// content (app glyph, back button) indents clear of them.
const double kTrafficLightInset = 78;

/// A stock-[AppBar] leading width that fits [trafficLightBackButton]. Pair the
/// two on any Material screen still using a default [AppBar] (the routes pushed
/// above the XP-chromed library) so the traffic lights don't cover the back
/// button.
const double kAppBarLeadingWidth = kTrafficLightInset + 48;

/// An automatic-style back button indented past the traffic lights. Use with
/// `leadingWidth: kAppBarLeadingWidth`.
Widget trafficLightBackButton() => const Padding(
  padding: EdgeInsets.only(left: kTrafficLightInset),
  child: BackButton(),
);

/// The Dart end of the runner's window channel. Because we hid the standard
/// title bar, the window can no longer be moved/zoomed by grabbing a system
/// title bar — these hand off to `NSWindow` so a designated region of our own
/// top bar restores those behaviors. System API only (no plugin, no dependency).
abstract final class WindowChrome {
  static const MethodChannel _channel = MethodChannel('anilocal/window');

  /// Begin a native window move-drag from the current mouse event.
  static Future<void> startDrag() => _channel.invokeMethod<void>('startDrag');

  /// Toggle zoom (maximize / restore) — the title-bar double-click behavior.
  static Future<void> toggleMaximize() =>
      _channel.invokeMethod<void>('toggleMaximize');

  /// **THE** fullscreen truth: whether the window is fullscreen right now,
  /// reported by the runner every time it changes (see
  /// `MainFlutterWindow.setBorderlessFullscreen`).
  ///
  /// Read this; never predict it. Callers used to flip their own flag next to
  /// the platform call, which meant the UI changed before the window did — a
  /// visibly mismatched intermediate layout — and went stale when something
  /// other than the ⛶ button drove the change. Everything now funnels through
  /// here, including the Cmd-Ctrl-F system shortcut (the runner intercepts
  /// `toggleFullScreen` and routes it into the same path).
  ///
  /// Fullscreen is BORDERLESS, not a macOS fullscreen Space: the runner resizes
  /// the window to the screen and hides the menu bar + Dock. There is therefore
  /// no ~400ms Space transition between the window moving and this notifier
  /// firing — the two land within a frame of each other, which is what makes
  /// the toggle read as one motion.
  ///
  /// It is also the moment to reclaim keyboard focus (see the player overlay).
  static ValueListenable<bool> get fullscreen => _fullscreen;
  static final ValueNotifier<bool> _fullscreen = ValueNotifier<bool>(false);

  /// Enter or leave borderless fullscreen. Fire-and-forget: the resulting state
  /// comes back on [fullscreen], so callers never set it themselves.
  static Future<void> setFullscreen(bool value) =>
      _channel.invokeMethod<void>('setFullscreen', value);

  static bool _initialized = false;

  /// Start listening for native window-state callbacks. Call once, from the
  /// composition root, before any UI reads [fullscreen]. Idempotent.
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullscreenChanged') {
        _fullscreen.value = call.arguments as bool? ?? false;
      }
      return null;
    });
  }
}

/// Wraps [child] so a click-drag inside it moves the window and a double-click
/// zooms it — the behaviors a real title bar provides, restored after we hid the
/// system one. Plain taps pass through (a pan needs movement to win the arena),
/// so any buttons inside [child] keep working.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowChrome.startDrag(),
      onDoubleTap: WindowChrome.toggleMaximize,
      child: child,
    );
  }
}
