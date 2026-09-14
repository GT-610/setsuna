import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/services/single_instance_service.dart';

void main() {
  test('activates the primary process when a second process starts', () async {
    final primary = SingleInstanceService(port: 0);
    final secondary = SingleInstanceService();
    final activated = Completer<void>();

    addTearDown(primary.release);
    addTearDown(secondary.release);

    expect(await primary.acquire(), SingleInstanceAcquireResult.acquired);
    primary.setOnActivate(() async {
      if (!activated.isCompleted) {
        activated.complete();
      }
    });

    final samePortSecondary = SingleInstanceService(port: primary.port);
    addTearDown(samePortSecondary.release);
    expect(
      await samePortSecondary.acquire(),
      SingleInstanceAcquireResult.existingInstanceActivated,
    );
    await activated.future.timeout(const Duration(seconds: 2));
  });

  test('refuses startup when a port conflict cannot be confirmed', () async {
    final conflictingServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(conflictingServer.close);
    conflictingServer.listen((socket) {
      socket.write('unexpected\n');
      socket.destroy();
    });

    final service = SingleInstanceService(port: conflictingServer.port);
    addTearDown(service.release);

    expect(
      await service.acquire(),
      SingleInstanceAcquireResult.unconfirmedConflict,
    );
  });
}
