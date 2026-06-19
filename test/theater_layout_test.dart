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

// Info has FINITE content height (120) so we can assert it sizes to content
// (no flex filler). Video/list are greedy (video is Expanded; list fills its
// rail box).
const double _infoContent = 120;

Map<TheaterZone, Widget> _zones() => {
  // Childless so they tolerate any size (incl. 0 in a tiny window) without
  // their own overflow — like the real media_kit Video / rail.
  TheaterZone.video: const ColoredBox(key: _videoKey, color: Color(0xFF112233)),
  TheaterZone.seriesInfo: const ColoredBox(
    key: _infoKey,
    color: Color(0xFF223344),
    child: SizedBox(height: _infoContent, width: double.infinity),
  ),
  TheaterZone.episodeList: const ColoredBox(
    key: _listKey,
    color: Color(0xFF334455),
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

  testWidgets('info sizes to content; video fills the rest; no gap', (
    tester,
  ) async {
    await _pump(tester, TheaterLayoutConfig.theaterDefault);
    final video = tester.getSize(find.byKey(_videoKey));
    final info = tester.getSize(find.byKey(_infoKey));
    // Info hugs its content height (not a fraction, not filling) — the fix.
    expect(info.height, _infoContent);
    // Video absorbs the remainder.
    expect(video.height, closeTo(800 - _infoContent, 0.5));
    // No flex-filler gap: video sits directly above info, info ends at the
    // column bottom (no dead whitespace below it).
    expect(
      tester.getBottomLeft(find.byKey(_videoKey)).dy,
      closeTo(tester.getTopLeft(find.byKey(_infoKey)).dy, 0.5),
    );
    expect(tester.getBottomLeft(find.byKey(_infoKey)).dy, closeTo(800, 0.5));
    // Default rail on the right => video's left edge is at x=0.
    expect(tester.getTopLeft(find.byKey(_videoKey)).dx, 0);
    // Main column width = total - rail (30%) = 70% of 1200.
    expect(video.width, closeTo(1200 * 0.70, 0.5));
  });

  testWidgets('short window: info content > height degrades, no overflow', (
    tester,
  ) async {
    // A window shorter than the info content (120) — the graceful-degradation
    // edge. Must clip/cap, never overflow (the bug we keep killing).
    await _pump(
      tester,
      TheaterLayoutConfig.theaterDefault,
      size: const Size(600, 80),
    );
    expect(tester.takeException(), isNull);
    // Info is clipped to the column rather than pushing past it.
    expect(tester.getSize(find.byKey(_infoKey)).height, lessThanOrEqualTo(80));
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
