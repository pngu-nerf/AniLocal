import 'package:flutter/services.dart';

import '../../diagnostics/app_log.dart';
import '../../diagnostics/diagnostics.dart';

/// Put the diagnostics report on the clipboard and say what happened. Two
/// buttons (the library's load-error screen and Settings › About) did this
/// with two failure sentences; the report, the copy and the words are one.
/// [extra] is appended under its own rule — the error the screen is showing.
/// Never throws: the one button meant for "something is wrong" must not fail
/// silently at the clipboard, so a refusal comes back as the sentence to show.
Future<String> copyDiagnostics({String? extra}) async {
  try {
    final report = await Diagnostics.report();
    final text = extra == null ? report : '$report\n\n--- error ---\n$extra';
    await Clipboard.setData(ClipboardData(text: text));
    return 'Copied ${AppLog.recent().length} log lines.';
  } catch (e, stack) {
    AppLog.error('Copy diagnostics failed', error: e, stack: stack);
    return 'Copy failed — the log file has it.';
  }
}
