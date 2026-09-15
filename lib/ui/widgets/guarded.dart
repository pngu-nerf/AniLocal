import 'dart:async';

import '../../diagnostics/app_log.dart';

/// Runs [action] so that a failure is LOGGED and handed to [onError] instead
/// of becoming an uncaught async error.
///
/// Every screen has reads and writes it fires without awaiting — a panel's
/// first load, a persist behind a switch, a reload after a dialog. Half of
/// them used to be bare `unawaited(...)` calls: a throw left a spinner
/// spinning forever, or a switch showing a value that was never stored, and
/// nothing in the log. This is the one shape they all take now. [what] names
/// the operation for the log line; [onError] is where a screen degrades its
/// own state (an error line instead of the spinner, a snackbar, a re-read).
Future<void> guarded(
  String what,
  Future<void> Function() action, {
  void Function(Object error)? onError,
}) async {
  try {
    await action();
  } catch (e, stack) {
    AppLog.error('$what failed', error: e, stack: stack);
    onError?.call(e);
  }
}

/// [guarded], fire-and-forget: for the call sites that were `unawaited`.
void fireAndForget(
  String what,
  Future<void> Function() action, {
  void Function(Object error)? onError,
}) => unawaited(guarded(what, action, onError: onError));
