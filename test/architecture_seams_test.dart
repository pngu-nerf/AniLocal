import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CLAUDE.md's seams, as a test rather than a habit. The UI reads through
/// repository interfaces and domain models; it never sees Drift, a metadata
/// source's module, the scanner or the pipeline. The domain depends on
/// nothing above it. Before this test the rule held only because every
/// change was read with it in mind.
///
/// Reads the source tree, not the analyzer: an import line is the seam.
void main() {
  test('lib/ui imports nothing from lib/data, lib/sync or package:drift', () {
    final offences = _offences('lib/ui', const [
      'package:drift/',
      'package:anilocal/data/',
      'package:anilocal/sync/',
      '/data/',
      '/sync/',
    ]);
    expect(offences, isEmpty, reason: offences.join('\n'));
  });

  test(
    'lib/domain imports nothing from lib/data, lib/sync, lib/ui or Flutter',
    () {
      final offences = _offences('lib/domain', const [
        'package:drift/',
        'package:flutter/',
        'package:anilocal/data/',
        'package:anilocal/sync/',
        'package:anilocal/ui/',
        '/data/',
        '/sync/',
        '/ui/',
      ]);
      expect(offences, isEmpty, reason: offences.join('\n'));
    },
  );
}

/// Every `import` line under [dir] whose target contains one of [forbidden].
/// Relative imports are resolved against the importing file first, so a
/// `../shared/` step that happens to contain the letters is not a hit, and a
/// forbidden directory reached by `../../data/x.dart` is.
List<String> _offences(String dir, List<String> forbidden) {
  final root = Directory(dir);
  expect(root.existsSync(), isTrue, reason: 'run from the package root');
  final hits = <String>[];
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  final line = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');
  for (final file in files) {
    var n = 0;
    for (final text in file.readAsLinesSync()) {
      n++;
      final m = line.firstMatch(text);
      if (m == null) continue;
      final target = m.group(1)!;
      final resolved =
          target.startsWith('package:') || target.startsWith('dart:')
          ? target
          : '/${_normalize('${file.parent.path}/$target')}';
      for (final bad in forbidden) {
        if (resolved.contains(bad)) {
          hits.add('${file.path}:$n imports $target');
          break;
        }
      }
    }
  }
  return hits;
}

String _normalize(String path) {
  final out = <String>[];
  for (final seg in path.split('/')) {
    if (seg == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      out.add(seg);
    }
  }
  return out.join('/');
}
