import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/models/settings.dart';
import 'package:setsuna/services/builtin_instance_service.dart';
import 'package:setsuna/services/builtin_engine_configuration.dart';
import 'package:setsuna/services/builtin_engine_capabilities.dart';
import 'package:setsuna/utils/app_paths.dart';

import 'support/memory_settings_repository.dart';

Future<void> _closeSockets(Iterable<ServerSocket> sockets) async {
  for (final socket in sockets) {
    await socket.close();
  }
}

Future<List<ServerSocket>> _reserveConsecutiveLoopbackPorts(int count) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final sockets = <ServerSocket>[
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    ];
    final firstPort = sockets.first.port;
    if (firstPort > 65535 - count) {
      await _closeSockets(sockets);
      continue;
    }

    try {
      for (var offset = 1; offset < count; offset++) {
        sockets.add(
          await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            firstPort + offset,
          ),
        );
      }
      return sockets;
    } on SocketException {
      await _closeSockets(sockets);
    }
  }
  throw StateError('Could not reserve $count consecutive loopback ports');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BuiltinInstanceService helper methods', () {
    late BuiltinInstanceService service;

    setUp(() {
      service = BuiltinInstanceService();
    });

    tearDown(() => service.dispose());

    test('unwraps repository settings snapshots', () {
      final snapshot = service.decodePersistedSettingsSnapshot(
        '{"schemaVersion":2,"settings":{"rpcListenPort":"16881"}}',
      );

      expect(snapshot, {'rpcListenPort': '16881'});
    });

    test('uses the bound loaded settings for the built-in instance', () async {
      final settings = Settings(
        repository: MemorySettingsRepository(<String, dynamic>{
          'rpcListenPort': 16882,
          'rpcSecret': 'secure-secret',
          'downloadDir': 'C:\\Downloads\\Setsuna',
        }),
      );
      await settings.loadSettings();
      addTearDown(settings.dispose);

      service.bindSettings(settings);

      final instance = service.getBuiltinInstanceConfig();
      expect(instance.port, 16882);
      expect(instance.secret, 'secure-secret');
      expect(instance.downloadDir, 'C:\\Downloads\\Setsuna');
    });

    final configuration = BuiltinEngineConfiguration({}, AppPaths.instance);
    test('resolves DHT port defaults, boundaries and persisted types', () {
      for (final entry in <Object?, int>{
        null: 26701,
        0: 26701,
        -1: 26701,
        70000: 26701,
        1: 1,
        65535: 65535,
        5000: 5000,
        '8080': 8080,
        '  5000  ': 5000,
        'abc': 26701,
        '99999': 26701,
        3.14: 26701,
      }.entries) {
        expect(
          configuration.resolveEffectiveDhtListenPort({
            'dhtListenPort': entry.key,
          }),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });
    test('resolves BT ports and configured paths without losing ranges', () {
      for (final entry in <Object?, String>{
        null: '6881-6999',
        '': '6881-6999',
        '   ': '6881-6999',
        '51413': '51413',
        '6881-6999': '6881-6999',
        ' 51413 ': '51413',
      }.entries) {
        expect(
          configuration.resolveEffectiveBtListenPort({
            'btListenPort': entry.key,
          }),
          entry.value,
        );
      }
      for (final entry in <Object?, String>{
        null: 'fallback',
        '': 'fallback',
        '  ': 'fallback',
        'custom/path': 'custom/path',
        ' custom/path ': 'custom/path',
      }.entries) {
        expect(
          configuration.resolveConfiguredFilePath(entry.key, 'fallback'),
          entry.value,
        );
      }
    });
    test('formats persisted speed limits with aria2 units', () {
      for (final entry in <Object?, String>{
        null: '0',
        'abc': '0',
        0: '0',
        -100: '0',
        1024: '1024K',
        128.5: '128K',
        '512': '512K',
      }.entries) {
        expect(configuration.formatSpeedLimitArg(entry.key), entry.value);
      }
    });
    test(
      'seeding overrides and persisted numeric fallbacks remain compatible',
      () {
        for (final entry in <Object?, int>{
          null: 60,
          'abc': 60,
          120: 120,
          '90': 90,
          90.5: 90,
        }.entries) {
          expect(
            configuration.effectiveSeedTime(false, entry.key),
            entry.value,
          );
          expect(configuration.effectiveSeedTime(true, entry.key), 525600);
        }
        for (final entry in <Object?, double>{
          null: 1,
          'abc': 1,
          2.5: 2.5,
          '3.0': 3,
          2: 2,
        }.entries) {
          expect(
            configuration.effectiveSeedRatio(false, entry.key),
            entry.value,
          );
          expect(configuration.effectiveSeedRatio(true, entry.key), 0);
        }
      },
    );
  });

  group('engine hardening helpers', () {
    test('sanitizeAllProxyArg rejects SOCKS schemes in any case', () {
      expect(
        BuiltinEngineConfiguration.sanitizeAllProxyArg('socks5://h:1'),
        null,
      );
      expect(
        BuiltinEngineConfiguration.sanitizeAllProxyArg('SOCKS5://h:1'),
        null,
      );
      expect(
        BuiltinEngineConfiguration.sanitizeAllProxyArg('socks4a://h:1'),
        null,
      );
      expect(
        BuiltinEngineConfiguration.sanitizeAllProxyArg('socks5h://h:1'),
        null,
      );
    });

    test('sanitizeAllProxyArg keeps HTTP and scheme-less proxies', () {
      expect(
        BuiltinEngineConfiguration.sanitizeAllProxyArg('http://127.0.0.1:7890'),
        'http://127.0.0.1:7890',
      );
      expect(
        BuiltinEngineConfiguration.sanitizeAllProxyArg('127.0.0.1:7890'),
        '127.0.0.1:7890',
      );
      expect(BuiltinEngineConfiguration.sanitizeAllProxyArg('   '), null);
    });

    test('sanitizedEngineEnvironment strips proxy variables', () {
      final env = BuiltinEngineConfiguration.sanitizedEngineEnvironment({
        'PATH': 'C:\\Windows',
        'HTTP_PROXY': 'http://proxy:8080',
        'https_proxy': 'http://proxy:8080',
        'ALL_PROXY': 'socks5://proxy:1080',
        'no_proxy': 'localhost',
      });

      expect(env['PATH'], 'C:\\Windows');
      // Blocked variables are removed from the inherited environment and
      // re-added as explicit empty overrides (lowercase canonical form).
      expect(env['http_proxy'], '');
      expect(env['https_proxy'], '');
      expect(env['all_proxy'], '');
      expect(env['no_proxy'], '');
      for (final name in ['HTTP_PROXY', 'ALL_PROXY']) {
        expect(env.containsKey(name), isFalse, reason: '$name should be gone');
      }
    });

    test('failed detach-share probe is retried instead of cached', () async {
      var calls = 0;

      Future<ProcessResult> runProbe(String _, List<String> _) async {
        calls++;
        if (calls == 1) {
          throw ProcessException('aria2c', const ['--version']);
        }
        return ProcessResult(1, 0, 'aria2 2.0.0', '');
      }

      final capabilities = BuiltinEngineCapabilities(runProcess: runProbe);

      expect(await capabilities.supportsDetachShareOnly('aria2c'), isFalse);
      expect(await capabilities.supportsDetachShareOnly('aria2c'), isTrue);
      expect(calls, 2);
    });

    test('successful unsupported detach-share probe caches false', () async {
      var calls = 0;

      Future<ProcessResult> runProbe(String _, List<String> _) async {
        calls++;
        return ProcessResult(1, 0, 'aria2 1.37.0', '');
      }

      final capabilities = BuiltinEngineCapabilities(runProcess: runProbe);

      expect(await capabilities.supportsDetachShareOnly('aria2c'), isFalse);
      expect(await capabilities.supportsDetachShareOnly('aria2c'), isFalse);
      expect(calls, 1);
    });

    test('recognizes aria2-next version output', () async {
      Future<ProcessResult> runProbe(String _, List<String> _) async {
        return ProcessResult(1, 0, 'aria2-next version 2.5.5', '');
      }

      final capabilities = BuiltinEngineCapabilities(runProcess: runProbe);

      expect(await capabilities.supportsDetachShareOnly('aria2c'), isTrue);
    });

    test('recognizes aria2 version output with a version label', () async {
      Future<ProcessResult> runProbe(String _, List<String> _) async {
        return ProcessResult(1, 0, 'aria2 version 2.5.5', '');
      }

      final capabilities = BuiltinEngineCapabilities(runProcess: runProbe);

      expect(await capabilities.supportsDetachShareOnly('aria2c'), isTrue);
    });

    test('recovery arguments isolate port, session, and log paths', () async {
      final directory = await Directory.systemTemp.createTemp(
        'setsuna-recovery-args-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final sessionPath = '${directory.path}${separator}aria2.session';
      final logPath = '${directory.path}${separator}aria2.log';
      final downloadDir = '${directory.path}${separator}downloads';
      final settings = Settings(
        repository: MemorySettingsRepository(<String, dynamic>{
          'rpcListenPort': 16800,
          'sessionPath': sessionPath,
          'logPath': logPath,
          'downloadDir': downloadDir,
        }),
      );
      await settings.loadSettings();
      addTearDown(settings.dispose);
      await File(sessionPath).create();

      final service = BuiltinInstanceService()..bindSettings(settings);
      final configuration = BuiltinEngineConfiguration(
        settings.toBuiltinInstanceSettings(),
        AppPaths.instance,
      );
      addTearDown(service.dispose);
      final normalArgs = configuration.buildArguments(detachShareOnly: false);
      expect(normalArgs, contains('--rpc-listen-port=16800'));
      expect(normalArgs, contains('--save-session=$sessionPath'));
      expect(normalArgs, contains('--input-file=$sessionPath'));
      expect(normalArgs, contains('--log=$logPath'));

      var recoveryArgs = configuration.buildArguments(
        detachShareOnly: false,
        rpcPortOverride: 16801,
        useRecoveryPaths: true,
      );
      expect(recoveryArgs, contains('--rpc-listen-port=16801'));
      expect(service.getBuiltinInstanceConfig().port, 16800);
      final recoverySessionArg = recoveryArgs.firstWhere(
        (argument) => argument.startsWith('--save-session='),
      );
      final recoveryLogArg = recoveryArgs.firstWhere(
        (argument) => argument.startsWith('--log='),
      );
      final recoverySessionPath = recoverySessionArg.substring(
        '--save-session='.length,
      );
      expect(recoverySessionPath, isNot(sessionPath));
      expect(recoverySessionPath, contains('recovery-16801'));
      expect(recoveryLogArg, isNot('--log=$logPath'));
      expect(recoveryLogArg, contains('recovery-16801'));
      expect(recoveryArgs, isNot(contains('--input-file=$sessionPath')));

      await File(recoverySessionPath).create();
      recoveryArgs = configuration.buildArguments(
        detachShareOnly: false,
        rpcPortOverride: 16801,
        useRecoveryPaths: true,
      );
      expect(recoveryArgs, contains('--input-file=$recoverySessionPath'));
    });

    test('resolveAvailableRpcPort skips occupied loopback ports', () async {
      final reserved = await _reserveConsecutiveLoopbackPorts(4);
      addTearDown(() => _closeSockets(reserved));
      final preferredPort = reserved.first.port;
      final expectedSocket = reserved.removeLast();
      final expectedPort = expectedSocket.port;
      await expectedSocket.close();

      final service = BuiltinInstanceService();
      final resolved = await service.resolveAvailableRpcPort(
        preferredPort,
        maxAttempts: 3,
      );

      expect(resolved, expectedPort);
    });

    test('resolveAvailableRpcPort keeps a free preferred port', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final freePort = probe.port;
      await probe.close();

      final service = BuiltinInstanceService();
      final resolved = await service.resolveAvailableRpcPort(freePort);

      expect(resolved, freePort);
    });
  });
}
