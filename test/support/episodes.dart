import 'package:anilocal/domain/models/episode.dart';

/// A present episode [n] of show [seriesId], anchored at its own number —
/// the episode three widget tests each built for themselves.
Episode testEpisode(
  int n, {
  int seriesId = 1,
  String? fileRef,
  String? title,
}) => Episode(
  number: n,
  anchoredNumber: n,
  seriesId: seriesId,
  fileRef: fileRef ?? '/lib/ep$n.mkv',
  title: title ?? 'Episode $n',
);
