import '../../domain/models/skip_mode.dart';

/// The ONE place a [SkipMode] becomes text, so the settings control and any
/// future player affordance can never drift apart.
String skipModeLabel(SkipMode mode) => switch (mode) {
  SkipMode.off => 'No skip',
  SkipMode.button => 'Skip button',
  SkipMode.auto => 'Auto skip',
};
