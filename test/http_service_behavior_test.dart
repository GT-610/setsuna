import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:setsuna/models/aria2_instance.dart';
import 'package:setsuna/models/settings.dart';
import 'package:setsuna/services/tracker_sync_service.dart';
import 'package:setsuna/services/update_check_service.dart';
import 'support/fake_rpc_client.dart';
import 'support/memory_settings_repository.dart';

class _Repository extends MemorySettingsRepository {
  _Repository(super.values);
  bool fail = false;
  @override
  Future<void> save(
    Map<String, dynamic> values, {
    bool credentialsBlocked = false,
  }) async {
    if (fail) throw StateError('save failed');
    await super.save(values, credentialsBlocked: credentialsBlocked);
  }
}

class _TrackerClient extends FakeRpcClient {
  Map<String, dynamic>? applied;
  bool closed = false;
  @override
  Future<bool> setGlobalOption(Map<String, dynamic> options) async {
    applied = options;
    return true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Setsuna',
      packageName: 'setsuna',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test(
    'tracker sync deduplicates, persists, pushes and respects interval',
    () async {
      var requests = 0;
      final httpClient = MockClient((_) async {
        requests++;
        return http.Response('udp://one\r\nudp://one\nhttps://two\n', 200);
      });
      addTearDown(httpClient.close);
      final repository = _Repository({
        'autoSyncTracker': true,
        'lastSyncTrackerTime': 0,
      });
      final settings = Settings(repository: repository);
      addTearDown(settings.dispose);
      await settings.loadSettings();
      final client = _TrackerClient();
      final service = TrackerSyncService(httpClient: httpClient);
      final instance = client.instance.copyWith(
        status: ConnectionStatus.connected,
      );
      expect(
        await service.syncBuiltinTrackersIfNeeded(
          settings,
          builtinInstance: instance,
          rpcClient: client,
        ),
        isTrue,
      );
      expect(settings.btTracker, 'udp://one,https://two');
      expect(client.applied, {'bt-tracker': 'udp://one,https://two'});
      expect(client.closed, isFalse);
      expect(repository.savedValues!['lastSyncTrackerTime'], greaterThan(0));
      expect(await service.syncBuiltinTrackersIfNeeded(settings), isFalse);
      expect(requests, 1);
    },
  );

  test(
    'tracker failures do not advance the successful sync timestamp',
    () async {
      var failNetwork = true;
      final httpClient = MockClient(
        (_) async => failNetwork
            ? http.Response('unavailable', 503)
            : http.Response('udp://one', 200),
      );
      addTearDown(httpClient.close);
      final repository = _Repository({
        'autoSyncTracker': true,
        'lastSyncTrackerTime': 0,
      });
      final settings = Settings(repository: repository);
      addTearDown(settings.dispose);
      await settings.loadSettings();
      final service = TrackerSyncService(httpClient: httpClient);
      await expectLater(
        service.syncBuiltinTrackersIfNeeded(settings),
        throwsException,
      );
      expect(settings.lastSyncTrackerTime, 0);
      failNetwork = false;
      repository.fail = true;
      await expectLater(
        service.syncBuiltinTrackersIfNeeded(settings),
        throwsStateError,
      );
      expect(settings.lastSyncTrackerTime, 0);
      repository.fail = false;
      expect(await service.syncBuiltinTrackersIfNeeded(settings), isTrue);
    },
  );

  test('disabled tracker synchronization makes no request', () async {
    final httpClient = MockClient(
      (_) async => throw StateError('unexpected network request'),
    );
    addTearDown(httpClient.close);
    final settings = Settings(
      repository: _Repository({'autoSyncTracker': false}),
    );
    addTearDown(settings.dispose);
    await settings.loadSettings();
    expect(
      await TrackerSyncService(
        httpClient: httpClient,
      ).syncBuiltinTrackersIfNeeded(settings),
      isFalse,
    );
  });

  for (final body in ['not json', '[]', '{}', '{"tag_name":123}']) {
    test('rejects malformed release response $body', () async {
      final httpClient = MockClient((_) async => http.Response(body, 200));
      addTearDown(httpClient.close);
      expect(
        (await UpdateCheckService(
          httpClient: httpClient,
        ).checkForUpdate()).isFailed,
        isTrue,
      );
    });
  }

  test(
    'coalesces update requests and recovers after transport failure',
    () async {
      final gate = Completer<http.Response>();
      final requested = Completer<void>();
      var calls = 0;
      final httpClient = MockClient((_) {
        calls++;
        if (calls == 1) requested.complete();
        return calls == 1
            ? gate.future
            : Future.value(http.Response('{"tag_name":"v1.1.0"}', 200));
      });
      addTearDown(httpClient.close);
      final service = UpdateCheckService(httpClient: httpClient);
      final first = service.checkForUpdate();
      final second = service.checkForUpdate();
      await requested.future;
      gate.completeError(TimeoutException('offline'));
      expect((await first).isFailed, isTrue);
      expect((await second).isFailed, isTrue);
      expect(calls, 1);
      expect((await service.checkForUpdate()).isUpdateAvailable, isTrue);
      expect(calls, 2);
    },
  );

  testWidgets('failed automatic checks leave timestamp available for retry', (
    tester,
  ) async {
    final httpClient = MockClient((_) async => http.Response('offline', 503));
    addTearDown(httpClient.close);
    final repository = _Repository({});
    final settings = Settings(repository: repository);
    addTearDown(settings.dispose);
    await settings.loadSettings();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await UpdateCheckService(
      httpClient: httpClient,
    ).autoCheckIfNeeded(settings, tester.element(find.byType(Scaffold)));
    expect(settings.lastUpdateCheckTimestamp, 0);
  });
}
