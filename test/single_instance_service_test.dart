import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/services/single_instance_service.dart';

void main() {
  test('activates the primary process when a second process starts', () async {
    final primary = SingleInstanceService(port: 0);
    final secondary = SingleInstanceService();
    final activated = Completer<void>();

    addTearDown(primary.release);
    addTearDown(secondary.release);

    expect(await primary.acquire(), isTrue);
    primary.setOnActivate(() async {
      if (!activated.isCompleted) {
        activated.complete();
      }
    });

    final samePortSecondary = SingleInstanceService(port: primary.port);
    addTearDown(samePortSecondary.release);
    expect(await samePortSecondary.acquire(), isFalse);
    await activated.future.timeout(const Duration(seconds: 2));
  });
}
