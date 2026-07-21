import 'package:anilocal/ui/theme/vfd_readout.dart';
import 'package:anilocal/ui/theme/xp_theme.dart';
import 'package:anilocal/ui/theme/xp_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The BODY type role is a single source of truth in the theme: bare `Text`
/// inherits Helvetica Neue in the matte body color — NOT the framework default
/// (Roboto), and NOT the lit cyan display hue. Guards the printed-vs-lit split.
void main() {
  testWidgets('bare body Text inherits the theme body role, not Roboto', (
    tester,
  ) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: XpTheme.data(),
        // Mirror the app's root DefaultTextStyle wrapper.
        builder: (context, child) => DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!,
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              style = DefaultTextStyle.of(ctx).style;
              return const Text('body');
            },
          ),
        ),
      ),
    );

    // Body font is the app sans, by inheritance from the theme.
    expect(style.fontFamily, Xp.fontFamily);
    expect(style.fontFamily, isNot('Roboto'));

    // Body color is the matte cream token — PRINTED, not the lit cyan display
    // color. This is the intentional printed-vs-lit distinction.
    expect(style.color, Xp.text);
    expect(style.color, isNot(Xp.accent));
  });

  test('display role (VfdReadout) is unaffected — still cyan phosphor', () {
    // The display role must stay lit cyan and separate from the body color.
    expect(const VfdReadout('12:00').color, Xp.accent);
    expect(Xp.accent, isNot(Xp.text));
  });
}
