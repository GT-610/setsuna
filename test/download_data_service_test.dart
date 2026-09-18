import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/models/aria2_instance.dart';
import 'package:setsuna/services/aria2_rpc_client.dart';
import 'package:setsuna/services/download_data_service.dart';

void main() {
  test('keeps stale tasks when one connected instance refresh fails', () async {
    Future<HttpServer> startServer(String gid) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': <Object>[
              <Object>[
                <Object>[
                  <String, String>{
                    'gid': gid,
                    'status': 'active',
                    'totalLength': '10',
                    'completedLength': '1',
                    'downloadSpeed': '1',
                    'uploadSpeed': '0',
                  },
                ],
              ],
              <Object>[<Object>[]],
              <Object>[<Object>[]],
            ],
          }),
        );
        await request.response.close();
      });
      return server;
    }

    final firstServer = await startServer('first');
    final secondServer = await startServer('second');
    final instances = <Aria2Instance>[
      Aria2Instance(
        id: 'one',
        name: 'One',
        type: InstanceType.remote,
        protocol: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: firstServer.port,
        status: ConnectionStatus.connected,
      ),
      Aria2Instance(
        id: 'two',
        name: 'Two',
        type: InstanceType.remote,
        protocol: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: secondServer.port,
        status: ConnectionStatus.connected,
      ),
    ];
    final service = DownloadDataService();

    await service.refreshTasks(instances);
    expect(
      service.tasks.map((task) => task.id),
      containsAll(<String>['first', 'second']),
    );

    await secondServer.close(force: true);
    await service.refreshTasks(instances);

    expect(
      service.tasks.map((task) => task.id),
      containsAll(<String>['first', 'second']),
    );
    expect(service.instanceStates['two']?.isStale, isTrue);
    expect(service.instanceStates['one']?.isStale, isFalse);

    service.dispose();
    await firstServer.close(force: true);
  });

  test(
    'clears tasks and instance state when all instances disconnect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': <Object>[
              <Object>[
                <Object>[
                  <String, String>{
                    'gid': 'connected',
                    'status': 'active',
                    'totalLength': '10',
                    'completedLength': '1',
                    'downloadSpeed': '1',
                    'uploadSpeed': '0',
                  },
                ],
              ],
              <Object>[<Object>[]],
              <Object>[<Object>[]],
            ],
          }),
        );
        await request.response.close();
      });
      final instance = Aria2Instance(
        id: 'disconnect',
        name: 'Disconnect',
        type: InstanceType.remote,
        protocol: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        status: ConnectionStatus.connected,
      );
      final service = DownloadDataService();

      await service.refreshTasks(<Aria2Instance>[instance]);
      expect(service.tasks.single.id, 'connected');
      expect(service.instanceStates, contains(instance.id));

      await service.refreshTasks(const <Aria2Instance>[]);

      expect(service.tasks, isEmpty);
      expect(service.instanceStates, isEmpty);
      service.dispose();
      await server.close(force: true);
    },
  );

  test('keeps stale tasks when a multicall item fails', () async {
    var failWaitingCall = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'result': <Object>[
            <Object>[
              <Object>[
                <String, String>{
                  'gid': 'kept',
                  'status': 'active',
                  'totalLength': '10',
                  'completedLength': '1',
                  'downloadSpeed': '1',
                  'uploadSpeed': '0',
                },
              ],
            ],
            if (failWaitingCall)
              <String, Object>{'code': 1, 'message': 'waiting failed'}
            else
              <Object>[<Object>[]],
            <Object>[<Object>[]],
          ],
        }),
      );
      await request.response.close();
    });
    final instance = Aria2Instance(
      id: 'partial',
      name: 'Partial',
      type: InstanceType.remote,
      protocol: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      status: ConnectionStatus.connected,
    );
    final service = DownloadDataService();

    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(service.tasks.single.id, 'kept');

    failWaitingCall = true;
    await service.refreshTasks(<Aria2Instance>[instance]);

    expect(service.tasks.single.id, 'kept');
    expect(service.instanceStates['partial']?.isStale, isTrue);
    service.dispose();
    await server.close(force: true);
  });

  test('queues one latest refresh while a refresh is in progress', () async {
    final firstRequestSeen = Completer<void>();
    final releaseFirstRequest = Completer<void>();
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestCount++;
      final requestNumber = requestCount;
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (requestNumber == 1) {
        firstRequestSeen.complete();
        await releaseFirstRequest.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'result': <Object>[
            <Object>[<Object>[]],
            <Object>[<Object>[]],
            <Object>[<Object>[]],
          ],
        }),
      );
      await request.response.close();
    });
    final instance = Aria2Instance(
      id: 'queue',
      name: 'Queue',
      type: InstanceType.remote,
      protocol: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      status: ConnectionStatus.connected,
    );
    final service = DownloadDataService();

    final firstRefresh = service.refreshTasks(<Aria2Instance>[instance]);
    await firstRequestSeen.future;
    final queuedRefresh = service.refreshTasks(<Aria2Instance>[instance]);
    releaseFirstRequest.complete();
    await Future.wait(<Future<void>>[firstRefresh, queuedRefresh]);

    // The cold refresh performs basic + detailed requests; the one coalesced
    // refresh then skips straight to details because the prior cycle needed
    // them. Multiple queued callers still produce only one extra cycle.
    expect(requestCount, 3);
    service.dispose();
    await server.close(force: true);
  });

  test('does not publish an in-flight refresh after disposal', () async {
    final requestSeen = Completer<void>();
    final releaseRequest = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      requestSeen.complete();
      await releaseRequest.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'result': <Object>[
            <Object>[
              <Object>[
                <String, String>{
                  'gid': 'late',
                  'status': 'active',
                  'totalLength': '10',
                  'completedLength': '1',
                  'downloadSpeed': '1',
                  'uploadSpeed': '0',
                },
              ],
            ],
            <Object>[<Object>[]],
            <Object>[<Object>[]],
          ],
        }),
      );
      await request.response.close();
    });
    final instance = Aria2Instance(
      id: 'dispose',
      name: 'Dispose',
      type: InstanceType.remote,
      protocol: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      status: ConnectionStatus.connected,
    );
    final service = DownloadDataService();
    var notificationCount = 0;
    service.addListener(() => notificationCount++);

    final refresh = service.refreshTasks(<Aria2Instance>[instance]);
    await requestSeen.future;
    service.dispose();
    releaseRequest.complete();
    await refresh;

    expect(notificationCount, 0);
    expect(service.tasks, isEmpty);
    await server.close(force: true);
  });

  test('refreshes tasks when aria2 sends a websocket notification', () async {
    WebSocket? socket;
    var gid = 'initial';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      socket = await WebSocketTransformer.upgrade(request);
      socket!.listen((message) {
        final decoded = jsonDecode(message as String) as Map<String, dynamic>;
        socket!.add(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': <Object>[
              <Object>[
                <Object>[
                  <String, String>{
                    'gid': gid,
                    'status': 'active',
                    'totalLength': '10',
                    'completedLength': '1',
                    'downloadSpeed': '1',
                    'uploadSpeed': '0',
                  },
                ],
              ],
              <Object>[<Object>[]],
              <Object>[<Object>[]],
            ],
          }),
        );
      });
    });
    final instance = Aria2Instance(
      id: 'events',
      name: 'Events',
      type: InstanceType.remote,
      protocol: 'ws',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      status: ConnectionStatus.connected,
    );
    final service = DownloadDataService();
    // Install the provider used by RPC notifications without leaving the
    // periodic refresh timer running during this test.
    service.startPeriodicRefresh(() => <Aria2Instance>[instance]);
    service.stopPeriodicRefresh();

    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(service.tasks.single.id, 'initial');

    final refreshed = Completer<void>();
    service.addListener(() {
      if (service.tasks.any((task) => task.id == 'updated') &&
          !refreshed.isCompleted) {
        refreshed.complete();
      }
    });
    gid = 'updated';
    socket!.add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'aria2.onDownloadStart',
        'params': <Object>[
          <String, String>{'gid': gid},
        ],
      }),
    );

    await refreshed.future.timeout(const Duration(seconds: 2));
    expect(service.tasks.single.id, 'updated');
    service.dispose();
    await server.close(force: true);
  });

  test('uses basic polling until task details are invalidated', () async {
    var requestCount = 0;
    final requestedProjections = <List<dynamic>>[];
    final fullTask = <String, dynamic>{
      'gid': 'bt-1',
      'status': 'active',
      'totalLength': '100',
      'completedLength': '10',
      'uploadLength': '1',
      'downloadSpeed': '5',
      'uploadSpeed': '1',
      'dir': '/downloads',
      'seeder': 'true',
      'numSeeders': '3',
      'infoHash': 'abc123',
      'bittorrent': <String, dynamic>{
        'info': <String, dynamic>{'name': 'Ubuntu ISO'},
      },
      'files': <Object>[
        <String, String>{
          'index': '1',
          'path': '/downloads/ubuntu.iso',
          'length': '100',
          'completedLength': '10',
          'selected': 'true',
        },
      ],
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestCount++;
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final calls = (decoded['params'] as List).single as List;
      final activeParams = List<dynamic>.from(
        (calls.first as Map)['params'] as List,
      );
      requestedProjections.add(
        activeParams.isNotEmpty && activeParams.last is List
            ? List<dynamic>.from(activeParams.last as List)
            : <dynamic>[],
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'result': <Object>[
            <Object>[fullTask],
            <Object>[<Object>[]],
            <Object>[<Object>[]],
          ],
        }),
      );
      await request.response.close();
    });
    final instance = Aria2Instance(
      id: 'stable',
      name: 'Stable',
      type: InstanceType.remote,
      protocol: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      status: ConnectionStatus.connected,
    );
    final service = DownloadDataService();

    // Cold refresh establishes a basic signature, then fetches details.
    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(service.tasks.single.name, 'Ubuntu ISO');
    expect(requestCount, 2);
    expect(requestedProjections.first, Aria2RpcClient.basicTaskFields);
    expect(requestedProjections[1], isEmpty);

    // The prior refresh needed details, so the next cycle skips the basic
    // projection. An unchanged detailed signature returns to cheap polling.
    final before = service.tasks.single;
    final beforeList = service.tasks;
    final beforeVersion = service.tasksVersion;
    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(requestCount, 3);
    expect(requestedProjections.last, isEmpty);
    expect(service.tasks.single.name, 'Ubuntu ISO');
    expect(identical(service.tasks.single, before), isTrue);

    expect(identical(service.tasks, beforeList), isTrue);
    expect(service.tasksVersion, beforeVersion);
    final stable = service.tasks.single;
    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(requestCount, 4);
    expect(requestedProjections.last, Aria2RpcClient.basicTaskFields);
    expect(identical(service.tasks.single, stable), isTrue);

    expect(identical(service.tasks, beforeList), isTrue);
    expect(service.tasksVersion, beforeVersion);
    fullTask['uploadLength'] = '2';
    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(requestCount, 6);
    expect(requestedProjections.last, isEmpty);
    expect(service.tasks.single.uploadLengthBytes, 2);
    expect(service.tasksVersion, beforeVersion + 1);

    (fullTask['files'] as List).single['selected'] = 'false';
    service.invalidateTaskDetails(instance.id);
    await service.refreshTasks(<Aria2Instance>[instance]);
    expect(requestCount, 7);
    expect(requestedProjections.last, isEmpty);
    expect(service.tasks.single.files!.single['selected'], 'false');
    expect(service.tasksVersion, beforeVersion + 2);
    expect(identical(service.tasks.single, before), isFalse);

    service.dispose();
    await server.close(force: true);
  });

  test('aggregates global stats reported by connected instances', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'result': <Object>[
            <Object>[<Object>[]],
            <Object>[<Object>[]],
            <Object>[<Object>[]],
            <Object>[
              <String, String>{
                'downloadSpeed': '2048',
                'uploadSpeed': '512',
                'numActive': '2',
                'numWaiting': '3',
                'numStopped': '4',
              },
            ],
          ],
        }),
      );
      await request.response.close();
    });
    final instance = Aria2Instance(
      id: 'stats',
      name: 'Stats',
      type: InstanceType.remote,
      protocol: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      status: ConnectionStatus.connected,
    );
    final service = DownloadDataService();

    expect(service.aggregatedGlobalSpeeds, isNull);

    await service.refreshTasks(<Aria2Instance>[instance]);

    expect(service.aggregatedGlobalSpeeds, (
      downloadSpeed: 2048,
      uploadSpeed: 512,
    ));
    service.dispose();
    await server.close(force: true);
  });
  test(
    'combines per-instance stats and fallback without stale global speed',
    () async {
      var failed = false;
      Future<HttpServer> server({required bool stats}) async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          request.response.write(
            jsonEncode({
              'id': body['id'],
              'jsonrpc': '2.0',
              'result': stats && failed
                  ? [
                      {'code': 1},
                      [],
                      [],
                    ]
                  : [
                      [
                        [
                          {
                            'gid': 'one',
                            'status': 'active',
                            'totalLength': '100',
                            'completedLength': '10',
                            'downloadSpeed': '10',
                            'uploadSpeed': '2',
                          },
                        ],
                      ],
                      [[]],
                      [[]],
                      if (stats)
                        [
                          {'downloadSpeed': '1000', 'uploadSpeed': '100'},
                        ],
                    ],
            }),
          );
          await request.response.close();
        });
        return server;
      }

      final withStats = await server(stats: true);
      final withoutStats = await server(stats: false);
      Aria2Instance instance(String id, HttpServer server) => Aria2Instance(
        id: id,
        name: id,
        type: InstanceType.remote,
        protocol: 'http',
        host: '127.0.0.1',
        port: server.port,
        status: ConnectionStatus.connected,
      );
      final instances = [
        instance('stats', withStats),
        instance('fallback', withoutStats),
      ];
      final service = DownloadDataService();
      addTearDown(service.dispose);
      await service.refreshTasks(instances);
      expect(service.taskSummary.speed, 1010);
      expect(service.totalUploadSpeed, 102);
      failed = true;
      await service.refreshTasks(instances);
      expect(service.instanceStates['stats']!.isStale, isTrue);
      expect(service.taskSummary.speed, 20);
      expect(service.totalUploadSpeed, 4);
      await service.refreshTasks([instances.last]);
      expect(service.taskSummary.speed, 10);
    },
  );
}
