import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/identified_episode.dart';
import 'library_services.dart';
import 'routes.dart';

/// Open fix-match for one unmatched file, from wherever the file was listed.
///
/// ONE implementation: the pre-check (the row is what the cache knows; the
/// file may have gone since the scan that wrote it), the prefilled search,
/// and the answer — true when an override was written, so the caller can
/// reload. The Unmatched panel in Settings and any future host share it
/// instead of each carrying a copy.
Future<bool> fixMatchFor(
  BuildContext context,
  LibraryServices services,
  IdentifiedEpisode file,
) async {
  if (!await File(file.filePath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "That file isn't there any more. Scan to update the list.",
          ),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  final done = await AppRoutes.fixMatch(
    context,
    services: services,
    filePaths: [file.filePath],
    prefillQuery: file.parsedTitle,
  );
  return done == true;
}
