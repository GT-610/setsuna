import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/models/aria2_instance.dart';
import 'package:setsuna/repositories/instance_repository.dart';
import 'package:setsuna/services/instance_manager.dart';

class _Repository extends InstanceRepository {
  Completer<void>? gate;
  bool failSave = false;
  bool failDelete = false;
  final saved = <List<Aria2Instance>>[];
  final deleted = <String>[];
  @override
  Future<void> save(
    List<Aria2Instance> values, {
    bool credentialsBlocked = false,
  }) async {
    await gate?.future;
    if (failSave) throw StateError('save failed');
    saved.add(List.of(values));
  }

  @override
  Future<void> deleteCredentials(String id) async {
    if (failDelete) throw StateError('cleanup failed');
    deleted.add(id);
  }
}

Aria2Instance _instance(String id, {int port = 6800}) => Aria2Instance(
  id: id,
  name: id,
  type: InstanceType.remote,
  protocol: 'http',
  host: '127.0.0.1',
  port: port,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repository repository;
  late InstanceManager manager;
  setUp(() {
    repository = _Repository();
    manager = InstanceManager(repository: repository);
  });
  tearDown(() => manager.dispose());

  test(
    'publishes only saved changes and recovers after save failure',
    () async {
      repository.gate = Completer<void>();
      final first = manager.addInstance(_instance('one'));
      final second = manager.addInstance(_instance('two'));
      await Future<void>.delayed(Duration.zero);
      expect(manager.instances, isEmpty);
      repository.gate!.complete();
      await Future.wait([first, second]);
      expect(manager.instances.map((i) => i.id), ['one', 'two']);
      expect(repository.saved.map((items) => items.length), [1, 2]);
      repository.failSave = true;
      await expectLater(
        manager.updateInstance(_instance('one').copyWith(name: 'changed')),
        throwsStateError,
      );
      await expectLater(manager.deleteInstance('one'), throwsStateError);
      expect(manager.instances.first.name, 'one');
      expect(manager.instances.length, 2);
      expect(repository.deleted, isEmpty);
      repository.failSave = false;
      await manager.updateInstance(_instance('one').copyWith(name: 'changed'));
      expect(manager.instances.first.name, 'changed');
      repository.failDelete = true;
      await manager.deleteInstance('one');
      expect(manager.instances.single.id, 'two');
      expect(repository.saved.last.single.id, 'two');
    },
  );

  test('rejects deleting an unknown instance', () async {
    await manager.addInstance(_instance('one'));
    await manager.addInstance(_instance('two'));
    final savedCount = repository.saved.length;

    await expectLater(manager.deleteInstance('missing'), throwsStateError);

    expect(manager.instances.map((instance) => instance.id), ['one', 'two']);
    expect(repository.saved.length, savedCount);
    expect(repository.deleted, isEmpty);
  });

  test('does not publish a save completed after disposal', () async {
    repository.gate = Completer<void>();
    var notifications = 0;
    manager.addListener(() => notifications++);
    final pending = manager.addInstance(_instance('one'));
    await Future<void>.delayed(Duration.zero);
    manager.dispose();
    repository.gate!.complete();
    await pending;
    expect(notifications, 0);
    expect(manager.instances, isEmpty);
    // Avoid disposing the same ChangeNotifier twice in teardown.
    manager = InstanceManager(repository: repository);
  });

  test('preserves connection health updated while a save is pending', () async {
    await manager.addInstance(_instance('one'));
    repository.gate = Completer<void>();
    final pending = manager.updateInstance(
      _instance('one').copyWith(name: 'renamed'),
    );
    await Future<void>.delayed(Duration.zero);
    manager.updateInstanceInList(
      'one',
      ConnectionStatus.connected,
      version: '2.0',
    );
    repository.gate!.complete();
    await pending;
    expect(manager.instances.single.name, 'renamed');
    expect(manager.instances.single.status, ConnectionStatus.connected);
    expect(manager.instances.single.version, '2.0');
  });

  test(
    'deduplicates connections and recovers from authorization failure',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var reject = true;
      var calls = 0;
      server.listen((request) async {
        calls++;
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        if (reject) {
          request.response.statusCode = 401;
        } else {
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'version': '2.5.5'},
            }),
          );
        }
        await request.response.close();
      });
      final instance = _instance('one', port: server.port);
      await manager.addInstance(instance);
      expect(await manager.connectInstance(instance), isFalse);
      expect(manager.instances.single.status, ConnectionStatus.failed);
      reject = false;
      calls = 0;
      expect(
        await Future.wait([
          manager.connectInstance(instance),
          manager.connectInstance(instance),
        ]),
        [true, true],
      );
      expect(calls, 2); // One connection probe and one version request.
      expect(manager.instances.single.status, ConnectionStatus.connected);
      manager.updateConnectionHealth(
        'one',
        isStale: true,
        consecutiveFailures: 2,
      );
      expect(manager.instances.single.status, ConnectionStatus.reconnecting);
      manager.updateConnectionHealth(
        'one',
        isStale: false,
        consecutiveFailures: 0,
      );
      expect(manager.instances.single.status, ConnectionStatus.connected);
      await manager.disconnectInstance(instance);
      expect(manager.instances.single.status, ConnectionStatus.disconnected);
    },
  );
}
