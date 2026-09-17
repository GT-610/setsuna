import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:setsuna/services/debug_log_store.dart';
import 'package:setsuna/utils/logging.dart';

void main() {
  setUp(DebugLogStore.clear);
  final originalLevel = Logger.root.level;
  tearDown(() {
    DebugLogStore.clear();
    Logger.root.level = originalLevel;
  });

  test('keeps only the newest log entries', () {
    for (var index = 0; index < DebugLogStore.maximumEntries + 5; index++) {
      DebugLogStore.add(
        LogRecord(Level.INFO, 'message-$index', 'Test'),
        message: 'message-$index',
        stackTrace: null,
      );
    }

    expect(
      DebugLogStore.entries.value,
      hasLength(DebugLogStore.maximumEntries),
    );
    expect(DebugLogStore.entries.value.first.message, 'message-5');
    expect(
      DebugLogStore.entries.value.last.message,
      'message-${DebugLogStore.maximumEntries + 4}',
    );
  });

  test('formats logger, level, message, and stack trace', () {
    final entry = DebugLogEntry(
      timestamp: DateTime(2026, 8, 12, 9, 5),
      loggerName: 'Rpc',
      level: Level.WARNING,
      message: 'Connection delayed',
      stackTrace: 'trace line',
    );

    expect(
      entry.plainText,
      '[09:05][Rpc][WARNING] Connection delayed\ntrace line',
    );
  });

  test('stores redacted stack traces from the root logger', () async {
    initializeAppLogging(level: Level.ALL);

    taggedLogger('Test').e(
      'RPC failed',
      stackTrace: StackTrace.fromString('authorization: Bearer private-token'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      DebugLogStore.entries.value.single.stackTrace,
      'authorization: [REDACTED]',
    );
  });
  test(
    'redacts URL credentials and sensitive headers in all log fields',
    () async {
      final printed = <String>[];
      await runZoned(
        () async {
          initializeAppLogging();
          taggedLogger('Test').e(
            'proxy http://alice:private-pass@proxy.example:8080/path',
            error: 'Cookie: session=private-cookie; other=private-other',
            stackTrace: StackTrace.fromString('X-API-Key: private-key'),
          );
          await Future<void>.delayed(Duration.zero);
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) {
            printed.add(line);
          },
        ),
      );
      expect(printed, isNotEmpty);
      final text = DebugLogStore.entries.value.single.plainText;
      for (final secret in [
        'alice',
        'private-pass',
        'private-cookie',
        'private-other',
        'private-key',
      ]) {
        expect(text, isNot(contains(secret)));
        expect(printed.join('\n'), isNot(contains(secret)));
      }
      expect(text, contains('http://[REDACTED]@proxy.example:8080/path'));
      expect(text, contains('[REDACTED]'));
    },
  );

  test('retains ordinary URLs and diagnostic text', () async {
    initializeAppLogging();
    taggedLogger('Test').w('GET https://example.org/files/a.zip failed: 503');
    await Future<void>.delayed(Duration.zero);
    expect(
      DebugLogStore.entries.value.single.message,
      'GET https://example.org/files/a.zip failed: 503',
    );
  });
}
