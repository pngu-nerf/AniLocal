import 'package:anilocal/ui/theater/theater_layout.dart';
import 'package:anilocal/ui/theater/theater_layout_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The layout seam under realistic constraints, with dummy zone content (no
/// playback engine). Catches the constraint bugs that paint a blank/black
/// screen — unbounded Expanded, zero-size zones, overflow.
const _videoKey = Key('VIDEO');
const _infoKey = Key('INFO');
const _listKey = Key('LIST');

Map<TheaterZone, Widget> _zones() => {
  TheaterZone.video: const ColoredBox(
    key: _videoKey,
    color: Color(0xFF112233),
    child: SizedBox.expand(child: Text('VIDEO')),
  ),
  TheaterZone.seriesInfo: const ColoredBox(
    key: _infoKey,
    color: Color(0xFF223344),
    child: SizedBox.expand(child: Text('INFO')),
  ),
  TheaterZone.episodeList: const ColoredBox(
    key: _listKey,
    color: Color(0xFF334455),
    child: SizedBox.expand(child: Text('LIST')),
  ),
};

Future<void> _pump(
  WidgetTester tester,
  TheaterLayoutConfig config, {
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TheaterLayout(config: config, zones: _zones()),
      ),
    ),
  );
}

void main() {
  testWidgets('default config lays out all three zones with real size', (
    tester,
  ) async {
    await _pump(tester, TheaterLayoutConfig.theaterDefault);
    // No layout exception, and every zone is present and non-zero.
    expect(tester.takeException(), isNull);
    for (final k in [_videoKey, _infoKey, _listKey]) {
      expect(find.byKey(k), findsOneWidget);
      expect(tester.getSize(find.byKey(k)).isEmpty, isFalse, reason: '$k');
    }
  });

  testWidgets('does not overflow when handed an UNBOUNDED height', (
    tester,
  ) async {
    // Reproduces the fullscreen-exit transient: a Column parent hands its
    // non-flex child maxHeight=Infinity. Pre-fix this made the video zone
    // SizedBox infinite -> ~100k "BOTTOM OVERFLOWED". Must clamp instead.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TheaterLayout(
                config: TheaterLayoutConfig.theaterDefault,
                zones: _zones(),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // It clamped to the view height and still laid the zones out.
    expect(find.byKey(_videoKey), findsOneWidget);
    expect(tester.getSize(find.byKey(_videoKey)).height, greaterThan(0));
  });

  testWidgets('video zone gets the bulk of the main column height', (
    tester,
  ) async {
    await _pump(tester, TheaterLayoutConfig.theaterDefault);
    final video = tester.getSize(find.byKey(_videoKey));
    final info = tester.getSize(find.byKey(_infoKey));
    expect(video.height, greaterThan(info.height));
    // Default rail on the right => video's left edge is at x=0.
    expect(tester.getTopLeft(find.byKey(_videoKey)).dx, 0);
    // Video + info stack vertically and fill the 800px height.
    expect(video.height + info.height, closeTo(800, 0.5));
    // Main column width = total - rail (30%) = 70% of 1200.
    expect(video.width, closeTo(1200 * 0.70, 0.5));
  });

  testWidgets('rail-left config moves the list to the left edge', (
    tester,
  ) async {
    await _pump(
      tester,
      TheaterLayoutConfig.theaterDefault.copyWith(railSide: TheaterSide.left),
    );
    expect(tester.takeException(), isNull);
    final listX = tester.getTopLeft(find.byKey(_listKey)).dx;
    final videoX = tester.getTopLeft(find.byKey(_videoKey)).dx;
    expect(listX, 0);
    expect(videoX, greaterThan(listX));
  });

  testWidgets('hiding the rail gives the main column the full width', (
    tester,
  ) async {
    await _pump(
      tester,
      TheaterLayoutConfig.theaterDefault.copyWith(
        visibleZones: const {TheaterZone.video, TheaterZone.seriesInfo},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(_listKey), findsNothing);
    expect(tester.getSize(find.byKey(_videoKey)).width, 1200);
  });
}
