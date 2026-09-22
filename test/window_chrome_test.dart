import 'package:anilocal/ui/window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The window channel is implemented by the macOS runner only. Elsewhere
/// every call must be a silent no-op — before this, a Windows or Linux build
/// threw MissingPluginException on every drag of the top bar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('anilocal/window');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });
  tearDown(() {
    WindowChrome.debugNativeOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('on macOS every call reaches the runner', () async {
    WindowChrome.debugNativeOverride = true;
    expect(WindowChrome.isNative, isTrue);
    expect(kTrafficLightInset, 78);
    await WindowChrome.startDrag();
    await WindowChrome.toggleMaximize();
    await WindowChrome.setFullscreen(true);
    await WindowChrome.setFullscreenAllowed(false);
    expect(calls, [
      'startDrag',
      'toggleMaximize',
      'setFullscreen',
      'setFullscreenAllowed',
    ]);
  });

  test('off macOS nothing is invoked, nothing throws, no inset', () async {
    WindowChrome.debugNativeOverride = false;
    expect(WindowChrome.isNative, isFalse);
    expect(kTrafficLightInset, 0);
    await WindowChrome.startDrag();
    await WindowChrome.toggleMaximize();
    await WindowChrome.setFullscreen(true);
    await WindowChrome.setFullscreenAllowed(false);
    expect(calls, isEmpty);
  });

  testWidgets('WindowDragArea is the bare child off macOS', (tester) async {
    WindowChrome.debugNativeOverride = false;
    await tester.pumpWidget(
      const WindowDragArea(child: SizedBox(key: Key('c'))),
    );
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byKey(const Key('c')), findsOneWidget);
  });
}
