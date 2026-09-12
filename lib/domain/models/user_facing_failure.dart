import 'metadata_failure.dart';

/// A failure the UI may show to the user, in words meant for them.
///
/// The UI must not import data-layer exception types (seam #1), yet it needs
/// to tell "the metadata service is down" from "that file is gone" from "a
/// scan is already running" without printing a raw exception. Every exception
/// the data and sync layers let reach a screen implements this; the ONE
/// renderer is `userFacingMessage` in the UI. An exception that is not one of
/// these gets a generic line and a pointer at the diagnostics.
abstract interface class UserFacingFailure {
  /// Whose end the fault is on, when the failure came from a remote source —
  /// the UI renders the shared copy for it. Null for a local condition.
  MetadataFailure? get failure;

  /// The message for a local condition, already written for the user.
  String get userMessage;
}
