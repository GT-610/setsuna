import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/models/aria2_instance.dart';
import 'package:setsuna/services/aria2_rpc_client.dart';

Aria2RpcClient _client(HttpServer server, {String protocol = 'http'}) =>
    Aria2RpcClient(
      Aria2Instance(
        id: 'test',
        name: 'Test',
        type: InstanceType.remote,
        protocol: protocol,
        host: '127.0.0.1',
        port: server.port,
      ),
      requestTimeout: const Duration(milliseconds: 100),
      maximumAttempts: 1,
    );

void main() {
  for (final code in [401, 403, 502]) {
    for (final body in ['', '<html>Access denied</html>']) {
      test('classifies HTTP $code with body length ${body.length}', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await request.drain<void>();
          request.response.statusCode = code;
          request.response.write(body);
          await request.response.close();
        });
        final client = _client(server);
        addTearDown(client.close);
        await expectLater(
          client.getVersion(),
          throwsA(
            code == 502
                ? isA<RpcException>().having(
                    (e) => e.message,
                    'status',
                    contains('502'),
                  )
                : isA<UnauthorizedException>(),
          ),
        );
      });
    }
  }

  for (final closeEarly in [false, true]) {
    test(
      'closes a late websocket after ${closeEarly ? 'client close' : 'timeout'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final arrived = Completer<void>();
        final allowUpgrade = Completer<void>();
        final closed = Completer<void>();
        server.listen((request) async {
          arrived.complete();
          await allowUpgrade.future;
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((_) {}, onDone: closed.complete);
        });
        final client = _client(server, protocol: 'ws');
        addTearDown(client.close);
        final pending = expectLater(
          client.getVersion(),
          throwsA(isA<ConnectionFailedException>()),
        );
        await arrived.future;
        if (closeEarly) await client.close();
        await pending;
        allowUpgrade.complete();
        await closed.future.timeout(const Duration(seconds: 3));
      },
    );
  }

  test('does not replay a submitted mutation after response loss', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var calls = 0;
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['method'], 'aria2.addUri');
      calls++;
      (await request.response.detachSocket()).destroy();
    });
    final client = _client(server);
    addTearDown(client.close);
    await expectLater(
      client.addUri(['https://example.org/file'], {}),
      throwsA(isA<RpcResultIndeterminateException>()),
    );
    expect(calls, 1);
  });
}
