import 'package:flutter/material.dart';

import '../metadata_failure_message.dart';
import '../theme/xp_tokens.dart';

/// How long a passing notice stays: the framework default for a plain line,
/// medium for a refusal the user should read ("that folder is already in
/// your library"), long for a failure they may want to act on.
const Duration kNoticeShort = Duration(seconds: 4);
const Duration kNoticeMedium = Duration(seconds: 6);
const Duration kNoticeLong = Duration(seconds: 8);

/// THE way the app speaks in a snackbar. Nineteen call sites each rebuilt
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(…)))`
/// and picked a duration of their own; this is the one place that shape and
/// those durations live. [replace] clears whatever is showing first — for a
/// status that supersedes the last one, not for a second independent fact.
/// [problem] paints the failure ground (`Xp.error`).
void showNotice(
  BuildContext context,
  String text, {
  Duration duration = kNoticeShort,
  bool replace = false,
  bool problem = false,
}) => showNoticeOn(
  ScaffoldMessenger.of(context),
  text,
  duration: duration,
  replace: replace,
  problem: problem,
);

/// [showNotice] for a caller that captured the messenger before its own
/// context went away (a Settings action that pops the window, then reports).
void showNoticeOn(
  ScaffoldMessengerState messenger,
  String text, {
  Duration duration = kNoticeShort,
  bool replace = false,
  bool problem = false,
}) {
  if (replace) messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      duration: duration,
      backgroundColor: problem ? Xp.error : null,
    ),
  );
}

/// A failure, in the one renderer's words: `lead` then `userFacingMessage`.
/// Failures stay [kNoticeLong] — the user may want to act on them.
void showFailure(
  BuildContext context,
  String lead,
  Object error, {
  Duration duration = kNoticeLong,
  bool replace = false,
}) => showNotice(
  context,
  '$lead ${userFacingMessage(error)}',
  duration: duration,
  replace: replace,
);

/// A write that did not land. Three panels said this in the same words.
void showWriteFailed(BuildContext context, Object error) =>
    showFailure(context, "That didn't save.", error);
