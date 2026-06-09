import 'package:anilocal/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AniLocalApp launches with its title', (tester) async {
    await tester.pumpWidget(const AniLocalApp());

    expect(find.text('AniLocal'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
