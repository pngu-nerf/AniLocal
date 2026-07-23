import 'package:anilocal/domain/models/episode.dart';
import 'package:anilocal/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// [PlaybackController.resumeStartFor] is the single rule for where an episode
/// starts: a watched/complete episode always replays from the beginning (its
/// saved resume position is ignored, not cleared); an unwatched one resumes.
void main() {
  Episode ep({required bool watched, required Duration resume}) => Episode(
    number: 1,
    fileRef: '/x.mkv',
    watched: watched,
    resumePosition: resume,
  );

  test('a watched episode starts at 0 (its resume position is ignored)', () {
    expect(
      PlaybackController.resumeStartFor(
        ep(watched: true, resume: const Duration(minutes: 22)),
      ),
      Duration.zero,
    );
  });

  test('an unwatched episode resumes where it left off', () {
    expect(
      PlaybackController.resumeStartFor(
        ep(watched: false, resume: const Duration(minutes: 10)),
      ),
      const Duration(minutes: 10),
    );
  });

  test('an unwatched episode with no progress starts at 0', () {
    expect(
      PlaybackController.resumeStartFor(
        ep(watched: false, resume: Duration.zero),
      ),
      Duration.zero,
    );
  });
}
