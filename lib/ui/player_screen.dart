import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../playback/playback_controller.dart';

/// Stage 1 walking skeleton: render one hardcoded local file embedded in-window
/// with libmpv (media_kit). Proves embedded video, ASS subtitle fidelity, and
/// seeking before anything else is built on top.
///
/// Set [kTestVideoPath] to an absolute path of a real fansub `.mkv` with styled
/// ASS subs. While empty, the app still launches and shows instructions.
///
/// NOTE: macOS TCC protects ~/Desktop, ~/Documents, ~/Downloads even for a
/// non-sandboxed app — a file there fails to open with no obvious error. Keep
/// test media outside those folders until folder-access is handled (Stage 5).
const String kTestVideoPath = '/Users/pngu/anilocal-test/test.mkv';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlaybackController _playback = PlaybackController();

  @override
  void initState() {
    super.initState();
    if (kTestVideoPath.isNotEmpty) {
      _playback.openFile(kTestVideoPath);
    }
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kTestVideoPath.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Set kTestVideoPath in lib/ui/player_screen.dart to a real .mkv '
            'with styled ASS subtitles to test playback.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Video brings the media_kit player controls overlay (seek bar included).
    return Video(controller: _playback.controller);
  }
}
