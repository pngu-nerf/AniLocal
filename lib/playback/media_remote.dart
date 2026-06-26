import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the macOS system media-remote integration — AirPods pinch, the
/// keyboard play/pause key, and Bluetooth (AVRCP) transport controls.
///
/// macOS only routes these events to the app that is the active *now-playing*
/// source, so the native side (`macos/Runner/MainFlutterWindow.swift`) does
/// BOTH halves: it registers `MPRemoteCommandCenter` handlers AND keeps
/// `MPNowPlayingInfoCenter` current. This Dart class is a thin ferry over the
/// method channel and deliberately holds NO play/pause logic: incoming commands
/// are forwarded to callbacks the owner wires to the SAME paths the on-screen
/// controls use (`Player.play`/`pause`/`playOrPause`, and the one
/// advance-to-next), never a parallel implementation.
///
/// Only macOS implements the native side today; on other platforms every call
/// is a no-op (the channel would otherwise raise `MissingPluginException`).
class MediaRemote {
  MediaRemote({
    required VoidCallback onPlay,
    required VoidCallback onPause,
    required VoidCallback onTogglePlayPause,
    required VoidCallback onNext,
  }) {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          onPlay();
        case 'pause':
          onPause();
        case 'togglePlayPause':
          onTogglePlayPause();
        case 'next':
          onNext();
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel('anilocal/media_remote');

  /// Publish the current playback state to the system now-playing center so the
  /// OS treats this app as the active media source (the precondition for it to
  /// deliver the remote commands at all). Cheap to call on every state change.
  Future<void> updateNowPlaying({
    required String title,
    required Duration duration,
    required Duration position,
    required bool playing,
  }) {
    if (!Platform.isMacOS) return Future<void>.value();
    return _channel.invokeMethod<void>('updateNowPlaying', <String, Object>{
      'title': title,
      'durationMs': duration.inMilliseconds,
      'positionMs': position.inMilliseconds,
      'playing': playing,
    });
  }

  /// Relinquish now-playing status and stop receiving commands. Call on dispose.
  void dispose() {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod<void>('clear');
  }
}
