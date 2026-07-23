import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/models/picture_mode.dart';
import '../theme/xp_tokens.dart';

/// Renders a show's cover through its [PictureMode] — the SINGLE cover renderer
/// used everywhere a cover shows (grid card, detail page, player series-info),
/// so a show's picture state is consistent in every view.
///
/// The cached image is NEVER altered or deleted; blur/remove are DISPLAY modes
/// over the always-retained file, so switching is instant and works offline:
///  - [PictureMode.normal] → the cached cover (or the default placeholder if the
///    show never had one),
///  - [PictureMode.blur]   → the cached cover rendered through a blur,
///  - [PictureMode.removed]→ a black placeholder with a question mark (the file
///    is kept, just not displayed).
///
/// Fills its parent; callers wrap it with their own sizing/clip (2:3 box, etc.).
class ShowCover extends StatelessWidget {
  const ShowCover({
    super.key,
    required this.imagePath,
    required this.pictureMode,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.movie_outlined,
    this.iconSize,
    this.blurSigma = 18,
  });

  /// The cached cover path (may be null, or point to a since-removed file).
  final String? imagePath;
  final PictureMode pictureMode;
  final BoxFit fit;

  /// Icon for the genuine NO-COVER case (never had art) — e.g. hourglass for a
  /// pending placeholder. Distinct from the "removed" question mark.
  final IconData placeholderIcon;
  final double? iconSize;
  final double blurSigma;

  /// Whether a cached cover file is actually present to display.
  static bool hasCover(String? imagePath) =>
      imagePath != null && File(imagePath).existsSync();

  @override
  Widget build(BuildContext context) {
    // Removed: black field + a question mark (the cached file is retained).
    if (pictureMode == PictureMode.removed) {
      return _placeholder(Icons.question_mark);
    }
    // No cached cover to show → the normal default placeholder. (Blur / reset
    // have nothing to act on here; callers disable those options.)
    if (!hasCover(imagePath)) return _placeholder(placeholderIcon);

    final image = Image.file(File(imagePath!), fit: fit);
    if (pictureMode == PictureMode.blur) {
      // Clip so the blur can't bleed past the cover's bounds.
      return ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: image,
        ),
      );
    }
    return image;
  }

  Widget _placeholder(IconData icon) => ColoredBox(
    color: Xp.well, // true-black display field
    child: Center(
      child: Icon(icon, color: Xp.textFaint, size: iconSize),
    ),
  );
}
