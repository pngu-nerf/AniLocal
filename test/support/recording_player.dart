import 'dart:async';

import 'package:media_kit/media_kit.dart';

const Stream<Never> _none = Stream<Never>.empty();

/// A native-free stand-in for media_kit's [Player]: it RECORDS what the app
/// asks of it (opens, seeks, every other method via `noSuchMethod`) and lets a
/// test EMIT the engine events the app listens to (position, duration,
/// playing, completed, error). [state] is a plain mutable field so a test can
/// set what `player.state.playing`/`rate`/`duration` read as.
///
/// Emitters update [state] before delivering the event, the way the real
/// engine does, so code that reads the state inside a listener sees the value
/// the event describes. Streams are synchronous so a test can assert straight
/// after `emit…`.
class RecordingPlayer implements Player {
  RecordingPlayer({this.state = const PlayerState()});

  @override
  PlayerState state;

  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _error = StreamController<String>.broadcast(sync: true);
  final _log = StreamController<PlayerLog>.broadcast(sync: true);

  @override
  late final PlayerStream stream = PlayerStream(
    _none, // playlist
    _playing.stream,
    _completed.stream,
    _position.stream,
    _duration.stream,
    _none, // volume
    _none, // rate
    _none, // pitch
    _none, // buffering
    _none, // bufferingPercentage
    _none, // buffer
    _none, // playlistMode
    _none, // shuffle
    _none, // audioParams
    _none, // videoParams
    _none, // audioBitrate
    _none, // audioDevice
    _none, // audioDevices
    _none, // track
    _none, // tracks
    _none, // width
    _none, // height
    _none, // subtitle
    _log.stream,
    _error.stream,
  );

  /// Every [open], in order.
  final List<Media> opened = [];

  /// Every [seek], in order.
  final List<Duration> seeks = [];

  /// Every other method call, recorded by `noSuchMethod`.
  final List<Invocation> calls = [];

  bool get positionHasListener => _position.hasListener;
  bool get durationHasListener => _duration.hasListener;

  bool called(Symbol member) => calls.any((c) => c.memberName == member);
  Invocation lastCall(Symbol member) =>
      calls.lastWhere((c) => c.memberName == member);

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add(playable as Media);
    // The real engine resets its position on open and reports it before the
    // seek to `start` lands — the phantom zero the session must ignore.
    state = state.copyWith(position: Duration.zero, completed: false);
    _position.add(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  void emitPosition(Duration p) {
    state = state.copyWith(position: p);
    _position.add(p);
  }

  void emitDuration(Duration d) {
    state = state.copyWith(duration: d);
    _duration.add(d);
  }

  void emitPlaying(bool playing) {
    state = state.copyWith(playing: playing);
    _playing.add(playing);
  }

  void emitCompleted() {
    state = state.copyWith(completed: true);
    _completed.add(true);
  }

  void emitError(String message) => _error.add(message);

  /// Close the event controllers (a test that hands the player to nothing
  /// else may call this at the end; the lint wants the sinks closable).
  Future<void> close() => Future.wait([
    _position.close(),
    _duration.close(),
    _playing.close(),
    _completed.close(),
    _error.close(),
    _log.close(),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) calls.add(invocation);
    // The player methods the app calls return Future<void>; the forwarder
    // type-checks the return, so hand back a Future (null would throw).
    return Future<void>.value();
  }
}
