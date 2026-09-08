import 'package:anilocal/domain/models/metadata_failure.dart';
import 'package:anilocal/domain/models/refresh_summary.dart';
import 'package:anilocal/ui/metadata_failure_message.dart';
import 'package:anilocal/ui/settings/settings_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sources.dart';

/// What the user is TOLD when metadata can't be fetched. The bug being pinned:
/// "Refresh metadata" swallowed an AniList outage and reported
/// "Refreshed 0 series · 0 skip sets fetched" — a success message for a run
/// that did nothing, which sends the user hunting for a local fault.
SettingsDialogActions _actions(RefreshSummary result) => SettingsDialogActions(
  sources: fakeSourcesActions(FakeSourcesRepository()),
  onRefreshMetadata: () async => result,
  onRefreshed: () {},
  loadUnmatchedCount: () async => 0,
  onOpenUnmatched: () {},
);

/// Opens a dialog and fires the real `refreshMetadata` action from inside it
/// (it pops its own route, so it needs a genuine dialog context).
Future<void> _runRefresh(WidgetTester tester, RefreshSummary result) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => TextButton(
                onPressed: () =>
                    refreshMetadata(dialogContext, _actions(result)),
                child: const Text('refresh'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('refresh'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an outage reports the failure, never a success count', (
    tester,
  ) async {
    await _runRefresh(
      tester,
      const RefreshSummary(
        seriesRefreshed: 0,
        skipsFetched: 0,
        failure: MetadataFailure.service,
      ),
    );

    expect(find.textContaining("AniList's API is down"), findsOneWidget);
    expect(
      find.textContaining('Refreshed'),
      findsNothing,
      reason:
          'a run that fetched nothing because AniList was down is not a '
          'successful refresh of zero series',
    );
  });

  testWidgets('being offline blames the connection, not AniList', (
    tester,
  ) async {
    await _runRefresh(
      tester,
      const RefreshSummary(
        seriesRefreshed: 0,
        skipsFetched: 0,
        failure: MetadataFailure.connection,
      ),
    );

    expect(
      find.textContaining('check your internet connection'),
      findsOneWidget,
    );
  });

  testWidgets('a successful refresh still reports its counts', (tester) async {
    await _runRefresh(
      tester,
      const RefreshSummary(seriesRefreshed: 4, skipsFetched: 2),
    );

    expect(find.textContaining('Refreshed 4 series'), findsOneWidget);
  });

  test('every failure kind has distinct, non-empty copy', () {
    final messages = {
      for (final f in MetadataFailure.values) f: metadataFailureCause(f),
    };

    expect(messages.values.any((m) => m.isEmpty), isFalse);
    expect(
      messages.values.toSet().length,
      MetadataFailure.values.length,
      reason:
          'each kind must say something different — otherwise splitting '
          'them told the user nothing new',
    );
  });
}
