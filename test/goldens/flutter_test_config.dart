import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies to every test under `test/goldens/` (flutter_test picks up the
/// nearest `flutter_test_config.dart`).
///
/// Golden images are rasterised by the engine, and the engine antialiases a
/// fraction of a pixel differently between an Intel Mac and an Apple-silicon
/// runner: the first CI run differed from the committed images by 1 to 5
/// pixels (0.01% of the image) and nothing else. Exact comparison therefore
/// cannot be the rule across machines. A diff under [_maxDiffPercent] passes;
/// anything above it fails with the usual failure images written next to the
/// golden. A colour, spacing or glyph change moves far more than a tenth of a
/// percent of the pixels, so the tolerance hides platform noise, not design
/// regressions.
class _TolerantFileComparator extends LocalFileComparator {
  _TolerantFileComparator(super.testFile);

  /// In PERCENT of pixels, the unit `ComparisonResult.diffPercent` reports.
  static const double _maxDiffPercent = 0.1;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _maxDiffPercent) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final base = goldenFileComparator;
  if (base is LocalFileComparator) {
    goldenFileComparator = _TolerantFileComparator(
      Uri.parse('${base.basedir}visual_identity_test.dart'),
    );
  }
  await testMain();
}
