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

  test("the reveal command per OS, with Explorer's one-token switch", () {
    (String, List<String>) on(String os, String path) =>
        Diagnostics.revealCommand(os, path)!;
    expect(on('macos', '/l/x.log').$1, 'open');
    expect(on('macos', '/l/x.log').$2, ['-R', '/l/x.log']);
    expect(on('windows', r'C:\l\x.log').$1, 'explorer.exe');
    expect(on('windows', r'C:\l\x.log').$2, [r'/select,C:\l\x.log']);
    expect(on('linux', '/l/x.log').$1, 'xdg-open');
    expect(on('linux', '/l/x.log').$2, ['/l']);
    expect(Diagnostics.revealCommand('fuchsia', '/l/x.log'), isNull);
  });
}
