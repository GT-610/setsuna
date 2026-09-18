import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:port_forwarder/port_forwarder.dart';
import 'package:setsuna/services/builtin_upnp_service.dart';
import 'package:setsuna/services/startup_integration_service.dart';
import 'package:setsuna/services/core_provisioning_service.dart';
import 'package:setsuna/utils/app_paths.dart';

class _Gateway implements Gateway {
  final opened = <(PortType, int)>[];
  final closed = <(PortType, int)>[];
  bool fail = false;
  bool reject = false;
  @override
  Future<bool> isMapped({
    required PortType protocol,
    required int externalPort,
  }) async => false;
  @override
  Future<bool> openPort({
    required PortType protocol,
    required int externalPort,
    int? internalPort,
    String portDescription = 'DartUPnP',
    int leaseDuration = 0,
  }) async {
    if (fail) throw StateError('gateway unavailable');
    if (reject) return false;
    opened.add((protocol, externalPort));
    return true;
  }

  @override
  Future<bool> closePort({
    required PortType protocol,
    required int externalPort,
  }) async {
    closed.add((protocol, externalPort));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Launcher implements LaunchAtStartup {
  bool enabled = false;
  bool fail = false;
  bool reject = false;
  int setups = 0;
  int changes = 0;
  @override
  void setup({
    required String appName,
    required String appPath,
    String? packageName,
    List<String> args = const [],
  }) {
    setups++;
  }

  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<bool> enable() async {
    if (fail) throw StateError('startup unavailable');
    if (reject) return false;
    changes++;
    enabled = true;
    return true;
  }

  @override
  Future<bool> disable() async {
    changes++;
    enabled = false;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('coalesces UPnP requests and removes established mappings', () async {
    final gateway = _Gateway();
    final discovery = Completer<Gateway?>();
    var discoveries = 0;
    final service = BuiltinUpnpService(
      discoverGateway: () {
        discoveries++;
        return discovery.future;
      },
    );
    final first = service.syncMappings(
      enabled: true,
      btListenPort: '6881-6999',
      dhtListenPort: 26701,
    );
    final duplicate = service.syncMappings(
      enabled: true,
      btListenPort: '6881-6999',
      dhtListenPort: 26701,
    );
    discovery.complete(gateway);
    await Future.wait([first, duplicate]);
    expect(discoveries, 1);
    expect(gateway.opened.toSet(), {
      (PortType.tcp, 6881),
      (PortType.udp, 26701),
    });
    await service.syncMappings(
      enabled: true,
      btListenPort: '6881-6999',
      dhtListenPort: 26701,
    );
    expect(gateway.opened.length, 2);
    await service.shutdown();
    expect(gateway.closed.toSet(), gateway.opened.toSet());
  });

  for (final reject in [false, true]) {
    test('retries a ${reject ? 'rejected' : 'failed'} UPnP mapping', () async {
      final gateway = _Gateway()
        ..fail = !reject
        ..reject = reject;
      final service = BuiltinUpnpService(discoverGateway: () async => gateway);
      await service.syncMappings(
        enabled: true,
        btListenPort: '7000',
        dhtListenPort: 0,
      );
      gateway
        ..fail = false
        ..reject = false;
      await service.syncMappings(
        enabled: true,
        btListenPort: '7000',
        dhtListenPort: 0,
      );
      expect(gateway.opened, [(PortType.tcp, 7000)]);
      await service.shutdown();
    });
  }

  test('startup changes are idempotent and failures can be retried', () async {
    final launcher = _Launcher();
    final service = StartupIntegrationService(launcher: launcher);
    await service.setEnabled(false);
    await service.setEnabled(true);
    await service.setEnabled(true);
    expect(launcher.setups, 1);
    expect(launcher.changes, 1);
    await service.setEnabled(false);
    launcher.fail = true;
    await expectLater(service.setEnabled(true), throwsStateError);
    launcher
      ..fail = false
      ..reject = true;
    await expectLater(service.setEnabled(true), throwsStateError);
    launcher.reject = false;
    await service.setEnabled(true);
    expect(launcher.enabled, isTrue);
  });

  test(
    'provisions bundled configuration once and falls back to assets',
    () async {
      final root = await Directory.systemTemp.createTemp('setsuna-provision-');
      addTearDown(() => root.delete(recursive: true));
      final bundle = await Directory('${root.path}/bundle').create();
      final support = Directory('${root.path}/support');
      final paths = AppPaths(
        supportDirectory: support,
        legacyPortableDirectory: root,
        bundledCoreDirectory: bundle,
      );
      final bundled = File('${bundle.path}/aria2.conf');
      await bundled.writeAsString('user-agent=bundled');
      final service = CoreProvisioningService(paths: paths);
      await service.ensureDefaultConfiguration();
      final target = File('${paths.coreDirectory.path}/aria2.conf');
      expect(await target.readAsString(), 'user-agent=bundled');
      await target.writeAsString('user-agent=custom');
      await service.ensureDefaultConfiguration();
      expect(await target.readAsString(), 'user-agent=custom');
      await target.delete();
      await bundled.delete();
      await service.ensureDefaultConfiguration();
      expect(await target.readAsString(), isNotEmpty);
    },
  );

  test('reports configuration write failures', () async {
    final root = await Directory.systemTemp.createTemp(
      'setsuna-provision-failure-',
    );
    addTearDown(() => root.delete(recursive: true));
    final paths = AppPaths(
      supportDirectory: root,
      legacyPortableDirectory: root,
      bundledCoreDirectory: root,
    );
    await File('${root.path}/core').writeAsString('blocks directory creation');
    await expectLater(
      CoreProvisioningService(paths: paths).ensureDefaultConfiguration(),
      throwsA(isA<CoreProvisioningException>()),
    );
  });
}
