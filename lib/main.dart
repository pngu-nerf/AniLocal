import 'package:flutter/material.dart';

import 'data/anilist/anilist_client.dart';
import 'ui/app.dart';

/// Stage 2: one hardcoded title to validate the AniList client + data seam.
const String kSearchTitle = 'Frieren';

/// Episodic anime formats — flip [kFormatFilter] to this to exclude MUSIC PVs
/// and other non-episodic noise from search.
const List<String> kEpisodicAnimeFormats = [
  'TV',
  'TV_SHORT',
  'MOVIE',
  'SPECIAL',
  'OVA',
  'ONA',
];

/// Search format allow-list. `null` = everything.
///
/// DECISION (revisit in Stage 3, see ROADMAP): `null`/everything is a Stage-2
/// spike convenience, NOT the intended product default. Case-2 recon showed the
/// "everything" search surfaces garbage — `Fate` returns the `Unmei` MUSIC PV
/// ahead of real Fate anime — and [kEpisodicAnimeFormats] fixes it. The product
/// will almost certainly ship with the filter ON; do not ship `everything` by
/// accident.
const List<String>? kFormatFilter = null;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Composition root: construct the data layer and hand the UI a domain Future.
  // The UI never sees AniListClient.
  final client = AniListClient();
  runApp(
    AniLocalApp(
      seriesFuture: client.fetchSeriesByTitle(
        kSearchTitle,
        formatsIn: kFormatFilter,
      ),
    ),
  );
}
