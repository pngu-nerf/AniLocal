import 'package:anilocal/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The report is pasted into public issues, so the home directory — the one
/// identifier in every path — is stripped. Windows names it USERPROFILE.
void main() {
  test('HOME is redacted to ~', () {
    expect(
      Diagnostics.redactHome(
        'log: /Users/pat/Library/Logs/x.log; folder /Users/pat/Anime',
        environment: const {'HOME': '/Users/pat'},
      ),
      'log: ~/Library/Logs/x.log; folder ~/Anime',
    );
  });

  test('USERPROFILE is the same thing on Windows', () {
    expect(
      Diagnostics.redactHome(
        r'folder C:\Users\pat\Videos\Anime',
        environment: const {'USERPROFILE': r'C:\Users\pat'},
      ),
      r'folder ~\Videos\Anime',
    );
  });

  test('no home known: the text is left alone', () {
    expect(
      Diagnostics.redactHome('x /Users/pat', environment: const {}),
      'x /Users/pat',
    );
  });
}
