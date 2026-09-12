import 'package:flutter_test/flutter_test.dart';

/// Finds an `XpButton` / `XpTitleTab` label by its ORIGINAL-case text.
///
/// Chrome labels render upper-case; this is the one place the tests know
/// that, so a change to the rendering (or to the widget these labels render
/// through) is a change here rather than in every test that taps a button.
Finder findXpLabel(String label) => find.text(label.toUpperCase());
