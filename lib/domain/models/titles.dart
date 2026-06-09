import 'package:equatable/equatable.dart';

/// The set of titles AniList exposes for a [Series].
///
/// All fields are nullable: AniList does not guarantee every title variant for
/// every entry. Pure domain value object — no JSON, no persistence concerns.
class Titles extends Equatable {
  const Titles({this.romaji, this.english, this.native});

  final String? romaji;
  final String? english;
  final String? native;

  @override
  List<Object?> get props => [romaji, english, native];
}
