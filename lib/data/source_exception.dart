import '../domain/models/metadata_failure.dart';

/// Base of every "a remote source failed" exception.
///
/// One message, one [MetadataFailure] saying whose end the fault is on, one
/// `toString`. The subtypes (`AniListException`, `KitsuException`, …) carry no
/// state of their own; they exist so a client's caller can catch THAT client's
/// failures specifically, and so a stack trace names the source. Before this
/// each of six classes re-declared the same three members.
///
/// [failure] defaults to [MetadataFailure.service] because blaming the user's
/// connection without evidence is the worse error: it sends them to debug a
/// working network.
abstract class SourceException implements Exception {
  const SourceException(this.message, {this.failure = MetadataFailure.service});

  final String message;
  final MetadataFailure failure;

  @override
  String toString() => '$runtimeType: $message';
}
