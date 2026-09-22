import 'dart:io' show Platform, exit;

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
/// content (app glyph, back button) indents clear of them. Zero on any other
/// platform: there the runner keeps its native frame (and its own controls), so
/// nothing floats over the bar.
double get kTrafficLightInset => WindowChrome.isNative ? 78 : 0;

/// The Dart end of the runner's window channel. Because we hid the standard
/// title bar, the window can no longer be moved/zoomed by grabbing a system
/// title bar — these hand off to `NSWindow` so a designated region of our own
/// top bar restores those behaviors. System API only (no plugin, no dependency).
abstract final class WindowChrome {
  static const MethodChannel _channel = MethodChannel('anilocal/window');

  /// Whether a runner implements this channel. Only the macOS runner does
  /// today; on any other platform every call here is a no-op, the way
  /// `MediaRemote` already behaves — the channel would otherwise raise
  /// `MissingPluginException` on every drag of the top bar. The HOST OS, not
  /// `defaultTargetPlatform` (which flutter_test reports as Android, and the
  /// header tests and goldens run against the real macOS chrome). A test that
  /// wants the other branch sets [debugNativeOverride].
  static bool get isNative => debugNativeOverride ?? Platform.isMacOS;

  /// Test-only: pretend to be (or not be) on the platform with the runner.
  @visibleForTesting
  static bool? debugNativeOverride;

  static Future<void> _invoke(String method, [Object? argument]) async {
    if (!isNative) return;
    await _channel.invokeMethod<void>(method, argument);
  }

  /// Begin a native window move-drag from the current mouse event.
  static Future<void> startDrag() => _invoke('startDrag');

  /// Toggle zoom (maximize / restore) — the title-bar double-click behavior.
  static Future<void> toggleMaximize() => _invoke('toggleMaximize');

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
      _invoke('setFullscreen', value);

  /// Declare whether a surface that can EXIT fullscreen is on screen.
  ///
  /// Only the player is. Borderless fullscreen hides the header and the traffic
  /// lights, so entering it from a browsing page leaves nothing to click — the
  /// user is trapped. Rather than crippling the green button everywhere, the
  /// runner refuses to ENGAGE fullscreen unless this is true, and does the
  /// ordinary macOS zoom instead.
  ///
  /// Turning this off while fullscreen is active exits immediately (enforced in
  /// the runner), so a player that disappears can't strand the window.
  static Future<void> setFullscreenAllowed(bool value) =>
      _invoke('setFullscreenAllowed', value);

  static bool _initialized = false;

  /// Start listening for native window-state callbacks. Call once, from the
  /// composition root, before any UI reads [fullscreen]. Idempotent.
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'fullscreenChanged':
          _fullscreen.value = call.arguments as bool? ?? false;
        case 'quitRequested':
          await runQuitHooks();
      }
      return null;
    });
  }

  // ---- quitting ----------------------------------------------------------

  /// Work that must finish before the process ends: the player's last
  /// position, the log's buffered lines, a scan's cancellation.
  ///
  /// Cmd-Q used to run NO Dart at all — the runner terminated, the tree was
  /// never unmounted, and whatever the 1-second save timer had not yet written
  /// was gone. Now the runner asks first (`applicationShouldTerminate` →
  /// `quitRequested`), waits for the reply, and terminates; every hook gets
  /// [quitHookBudget] in total, so a hook that hangs cannot hold the quit.
  /// Returns a function that removes the hook (call it on dispose).
  static VoidCallback addQuitHook(Future<void> Function() hook) {
    _quitHooks.add(hook);
    return () => _quitHooks.remove(hook);
  }

  static final List<Future<void> Function()> _quitHooks = [];

  /// The longest a quit waits for its hooks — matched by the runner's own
  /// fallback timer, so an unresponsive Dart side never blocks Cmd-Q.
  static const Duration quitHookBudget = Duration(seconds: 2);

  /// Run every quit hook, all at once, bounded by [quitHookBudget]. A hook
  /// that throws is logged by its owner and does not stop the others.
  static Future<void> runQuitHooks() async {
    final hooks = List.of(_quitHooks); // hooks may remove themselves
    await Future.wait([
      for (final hook in hooks) hook().catchError((Object _) {}),
    ]).timeout(quitHookBudget, onTimeout: () => const []);
  }

  /// Quit the app the way Cmd-Q does: through the runner, so the quit hooks
  /// run first. Used by the library's "reset cache" flow, which needs the
  /// database closed and the process gone before it can reopen empty.
  static Future<void> quit() async {
    if (isNative) return _channel.invokeMethod<void>('quit');
    // No runner to ask: run the hooks ourselves, then end the process.
    await runQuitHooks();
    debugExit(0);
  }

  /// How [quit] ends the process where there is no runner: `dart:io`'s
  /// `exit`. Replaceable so a test can reach that branch without killing the
  /// test runner.
  @visibleForTesting
  static void Function(int code) debugExit = exit;
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
    // A native frame does the moving where there is one; wrapping would only
    // swallow pans for nothing.
    if (!WindowChrome.isNative) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowChrome.startDrag(),
      onDoubleTap: WindowChrome.toggleMaximize,
      child: child,
    );
  }
}
