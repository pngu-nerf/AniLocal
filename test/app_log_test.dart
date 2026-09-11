import 'dart:io';

import 'package:anilocal/diagnostics/app_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  test('the ring keeps the most recent lines and drops the oldest', () {
    for (var i = 0; i < AppLog.ringCapacity + 50; i++) {
      AppLog.info('line $i');
    }
    final recent = AppLog.recent();
    expect(recent.length, AppLog.ringCapacity);
    expect(recent.first, contains('line 50'), reason: 'oldest 50 dropped');
    expect(recent.last, contains('line ${AppLog.ringCapacity + 49}'));
  });

  test('levels, errors and stacks are all in the line', () {
    AppLog.warn(
      'disk',
      error: const FormatException('bad'),
      stack: StackTrace.current,
    );
    final line = AppLog.recent().single;
    expect(line, contains('WARN'));
    expect(line, contains('disk'));
    expect(line, contains('FormatException: bad'));
    expect(line, contains('app_log_test'), reason: 'the stack is appended');
  });

  test(
    'attaching a file writes new lines AND carries the ring across',
    () async {
      final dir = await Directory.systemTemp.createTemp('anilocal_log_');
      addTearDown(() => dir.delete(recursive: true));
      AppLog.info('before attach');

      await AppLog.attachFile(() async => dir);
      AppLog.info('after attach');

      final text = await File('${dir.path}/app.log').readAsString();
      expect(
        text,
        contains('before attach'),
        reason: 'startup lines are not lost',
      );
      expect(text, contains('after attach'));
      expect(AppLog.filePath, endsWith('app.log'));
    },
  );

  test('rotates past the cap, keeping one backup', () async {
    final dir = await Directory.systemTemp.createTemp('anilocal_log_');
    addTearDown(() => dir.delete(recursive: true));
    await AppLog.attachFile(() async => dir);

    final big = 'x' * 4096;
    for (var i = 0; i < (AppLog.maxFileBytes ~/ 4096) + 4; i++) {
      AppLog.info(big);
    }

    expect(
      File('${dir.path}/app.log.1').existsSync(),
      isTrue,
      reason: 'backup',
    );
    expect(
      File('${dir.path}/app.log').lengthSync(),
      lessThan(AppLog.maxFileBytes),
      reason: 'the live file started over',
    );
  });

  test('an unwritable location never throws — the ring keeps going', () async {
    // A logger that can crash the thing it observes is worse than none.
    await AppLog.attachFile(() async => Directory('/dev/null/not/a/dir'));
    AppLog.info('still fine');
    expect(AppLog.filePath, isNull);
    expect(AppLog.recent().single, contains('still fine'));
  });

  test('dump() is the ring, joined — what Copy diagnostics pastes', () {
    AppLog.info('one');
    AppLog.error('two');
    expect(AppLog.dump().split('\n').length, 2);
  });
}
