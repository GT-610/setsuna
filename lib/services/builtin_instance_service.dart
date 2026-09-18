import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/aria2_instance.dart';
import '../models/settings.dart';
import '../utils/app_data_dir.dart';
import '../utils/app_paths.dart';
import '../utils/default_download_directory.dart';
import '../utils/atomic_file.dart';
import '../utils/logging.dart';
import 'aria2_rpc_client.dart';
import 'builtin_engine_configuration.dart';
import 'builtin_engine_capabilities.dart';
import 'builtin_upnp_service.dart';
import 'process_lifecycle_service.dart';

enum BuiltinInstanceApplyMode { none, liveApply, restartRequired }

/// Service class for managing the built-in Aria2 instance
class BuiltinInstanceService with Loggable {
  static const Duration _rpcShutdownTimeout = Duration(seconds: 5);

  /// Set when the engine recovered from an RPC port conflict by moving to a
  /// different port. The UI surfaces the message once and clears it.
  static final ValueNotifier<String?> portRecoveryNotice =
      ValueNotifier<String?>(null);

  final _capabilities = BuiltinEngineCapabilities();

  static BuiltinInstanceService? _instance;
  Process? _aria2Process;
  String? _aria2cPath;
  String? _aria2ConfPath;
  File? _pidFile;
  int? _managedPid;
  bool _isConnected = false;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final BuiltinUpnpService _upnpService = BuiltinUpnpService();
  BuiltinInstanceApplyMode _pendingApplyMode = BuiltinInstanceApplyMode.none;
  Future<void> _lifecycleTail = Future<void>.value();
  String? _lastStartError;
  Settings? _settings;
  int? _activeRpcPort;

  factory BuiltinInstanceService() {
    _instance ??= BuiltinInstanceService._internal();
    return _instance!;
  }

  BuiltinInstanceService._internal() {
    _initializePaths();
  }

  void bindSettings(Settings settings) {
    _settings = settings;
  }

  void _initializePaths() {
    final paths = AppPaths.instance;
    final coreDirPath = paths.coreDirectory.path;
    final coreDir = Directory(coreDirPath);

    if (!coreDir.existsSync()) {
      w('Core directory does not exist: $coreDirPath, creating it...');
      coreDir.createSync(recursive: true);
    }

    _aria2cPath = p.join(
      paths.bundledCoreDirectory.path,
      'aria2c${Platform.isWindows ? '.exe' : ''}',
    );
    _aria2ConfPath = p.join(coreDirPath, 'aria2.conf');
    _pidFile = File(p.join(coreDirPath, 'aria2.pid'));
  }

  String _getSettingsFilePath() {
    final dataDir = getAppDataDirectory();
    final configDir = Directory(p.join(dataDir.path, 'config'));
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }
    return p.join(configDir.path, 'settings.json');
  }

  Map<String, dynamic> _readSettingsSnapshot() {
    final settings = _settings;
    if (settings != null) {
      return settings.toBuiltinInstanceSettings();
    }

    try {
      final file = File(_getSettingsFilePath());
      if (!file.existsSync()) {
        return {};
      }
      final content = file.readAsStringSync();
      return decodePersistedSettingsSnapshot(content);
    } catch (e, stackTrace) {
      this.e(
        'Failed to read built-in settings snapshot',
        error: e,
        stackTrace: stackTrace,
      );
    }
    return {};
  }

  @visibleForTesting
  Map<String, dynamic> decodePersistedSettingsSnapshot(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return {};
    }

    final storedSettings = decoded['settings'];
    if (storedSettings is Map<String, dynamic>) {
      return Map<String, dynamic>.from(storedSettings);
    }
    return Map<String, dynamic>.from(decoded);
  }

  BuiltinEngineConfiguration get _configuration =>
      BuiltinEngineConfiguration(_readSettingsSnapshot(), AppPaths.instance);

  String? validateBuiltinFiles() {
    final requiredFiles = <({String label, String path})>[
      (label: 'aria2c', path: _aria2cPath!),
      (label: 'aria2.conf', path: _aria2ConfPath!),
    ];

    for (final fileInfo in requiredFiles) {
      final file = File(fileInfo.path);
      if (!file.existsSync()) {
        if (fileInfo.label == 'aria2c' && !Platform.isWindows) {
          return 'Built-in aria2 is not bundled for this platform. Remote instances remain available.';
        }
        return 'Missing ${fileInfo.label}: ${fileInfo.path}';
      }

      RandomAccessFile? handle;
      try {
        handle = file.openSync(mode: FileMode.read);
      } catch (e) {
        return 'Cannot open ${fileInfo.label}: ${fileInfo.path} ($e)';
      } finally {
        handle?.closeSync();
      }
    }

    return null;
  }

  String getEffectiveSessionPath() {
    final settings = _readSettingsSnapshot();
    return _configuration.getSessionPath(settings);
  }

  BuiltinInstanceApplyMode get pendingApplyMode => _pendingApplyMode;
  String? get lastStartError => _lastStartError;

  void markPendingApply(BuiltinInstanceApplyMode mode) {
    if (_pendingApplyMode == BuiltinInstanceApplyMode.restartRequired &&
        mode != BuiltinInstanceApplyMode.restartRequired) {
      return;
    }
    if (_pendingApplyMode == BuiltinInstanceApplyMode.liveApply &&
        mode == BuiltinInstanceApplyMode.none) {
      return;
    }
    _pendingApplyMode = mode;
  }

  void clearPendingApply({BuiltinInstanceApplyMode? appliedMode}) {
    if (appliedMode == null ||
        appliedMode == BuiltinInstanceApplyMode.restartRequired) {
      _pendingApplyMode = BuiltinInstanceApplyMode.none;
      return;
    }

    if (appliedMode == BuiltinInstanceApplyMode.liveApply &&
        _pendingApplyMode == BuiltinInstanceApplyMode.liveApply) {
      _pendingApplyMode = BuiltinInstanceApplyMode.none;
    }
  }

  Future<bool> resetSessionFile() async {
    final sessionPath = getEffectiveSessionPath();

    if (isRunning()) {
      final stopped = await stopInstance();
      if (!stopped) {
        throw Exception('Failed to stop the built-in instance before reset');
      }
    }

    final file = File(sessionPath);
    if (!file.existsSync()) {
      return false;
    }

    try {
      await file.delete();
      return true;
    } catch (e, stackTrace) {
      this.e(
        'Failed to reset built-in session file',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> syncUpnpStateForRunningInstance() async {
    if (!isRunning()) {
      return;
    }

    final settings = _readSettingsSnapshot();
    await _upnpService.syncMappings(
      enabled: settings['enableUpnp'] == true,
      btListenPort: _configuration.resolveEffectiveBtListenPort(settings),
      dhtListenPort: _configuration.resolveEffectiveDhtListenPort(settings),
    );
  }

  Future<T> _serializeLifecycle<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lifecycleTail = _lifecycleTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> startInstance() => _serializeLifecycle(_startInstance);

  Future<bool> _startInstance() async {
    try {
      _isConnected = false;
      _lastStartError = null;

      final validationError = validateBuiltinFiles();
      if (validationError != null) {
        _lastStartError = validationError;
        e(
          'Built-in Aria2 files are not ready, cannot start instance: '
          '$validationError',
        );
        return false;
      }

      if (!await ProcessLifecycleService.instance.canManageBuiltinProcess()) {
        _lastStartError =
            'Another Setsuna window is already managing the built-in aria2 instance';
        e(
          'Another Setsuna process owns the built-in aria2 lifecycle lock; '
          'refusing to start a duplicate process',
        );
        return false;
      }

      if (_aria2Process != null) {
        w(
          'Built-in Aria2 process is already running, PID: ${_aria2Process!.pid}',
        );
        return true;
      }

      if (await _adoptPersistedProcess()) {
        i('Adopted existing built-in Aria2 process, PID: $_managedPid');
        return true;
      }

      final legacyPid = await ProcessLifecycleService.instance
          .findExpectedProcess(
            port: _configuration.getRpcPort(_readSettingsSnapshot()),
            executablePath: _aria2cPath!,
          );
      if (legacyPid != null) {
        _managedPid = legacyPid;
        await _persistManagedPid(legacyPid);
        await ProcessLifecycleService.instance.attachToAppLifecycle(legacyPid);
        i('Adopted legacy built-in Aria2 process, PID: $legacyPid');
        return true;
      }

      if (await _isRpcReachable()) {
        // An unmanaged aria2 answers on the configured port; fall through to
        // the TCP-based recovery below which migrates us to a free port.
        w(
          'An unmanaged aria2 instance is answering on the configured built-in '
          'RPC port; looking for a free port',
        );
      }

      final configuredRpcPort = _configuration.getRpcPort(
        _readSettingsSnapshot(),
      );
      final resolvedRpcPort = await resolveAvailableRpcPort(configuredRpcPort);
      final recoveredFromPortCollision = resolvedRpcPort != configuredRpcPort;
      if (recoveredFromPortCollision) {
        await _persistRpcPort(resolvedRpcPort);
        final notice =
            'RPC port $configuredRpcPort was busy; moved the built-in '
            'instance to $resolvedRpcPort';
        portRecoveryNotice.value = notice;
        w(notice);
      }

      final args = _configuration.buildArguments(
        detachShareOnly: await _capabilities.supportsDetachShareOnly(
          _aria2cPath!,
        ),
        rpcPortOverride: resolvedRpcPort,
        useRecoveryPaths: recoveredFromPortCollision,
      );
      final process = await Process.start(
        _aria2cPath!,
        args,
        runInShell: false,
        mode: ProcessStartMode.normal,
        environment: BuiltinEngineConfiguration.sanitizedEngineEnvironment(
          Platform.environment,
        ),
        includeParentEnvironment: false,
      );
      _aria2Process = process;
      _managedPid = process.pid;
      _activeRpcPort = resolvedRpcPort;
      try {
        await _persistManagedPid(process.pid);
        if (!await ProcessLifecycleService.instance.attachToAppLifecycle(
          process.pid,
        )) {
          w(
            'Built-in Aria2 process ${process.pid} could not be attached to the '
            'application lifecycle safety net',
          );
        }
      } catch (_) {
        process.kill();
        _aria2Process = null;
        _managedPid = null;
        _activeRpcPort = null;
        rethrow;
      }

      process.exitCode.then((exitCode) {
        w('Built-in Aria2 process exited with code: $exitCode');
        if (identical(_aria2Process, process)) {
          _aria2Process = null;
          _managedPid = null;
          _isConnected = false;
          _activeRpcPort = null;
          unawaited(_deletePidFileIfMatches(process.pid));
          unawaited(_upnpService.shutdown());
        }
      });

      _monitorProcessOutput(process);

      return true;
    } catch (e, stackTrace) {
      _lastStartError = 'Failed to start built-in aria2: $e';
      this.e(
        'Failed to start built-in Aria2 instance',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> stopInstance() => _serializeLifecycle(_stopInstance);

  Future<bool> _stopInstance() async {
    try {
      if (_aria2Process == null && !await _adoptPersistedProcess()) {
        if (await _isRpcReachable()) {
          w(
            'Built-in aria2 RPC is reachable but the process is not owned by '
            'this Setsuna process; leaving it untouched',
          );
          return false;
        }
        w('Built-in Aria2 process is not running');
        await _clearManagedProcessState();
        return true;
      }

      try {
        await _shutdownThroughRpcIfPossible().timeout(_rpcShutdownTimeout);
      } on TimeoutException {
        w(
          'Timed out waiting for built-in Aria2 RPC shutdown, terminating process',
        );
        _aria2Process?.kill();
      }

      final process = _aria2Process;
      final managedPid = _managedPid;
      if (process != null) {
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          w(
            'Built-in Aria2 did not exit after RPC shutdown, terminating process',
          );
          process.kill();
          await process.exitCode.timeout(const Duration(seconds: 5));
        }
      } else if (managedPid != null &&
          await ProcessLifecycleService.instance.isExpectedProcess(
            managedPid,
            _aria2cPath!,
          )) {
        Process.killPid(managedPid);
        await _waitForPidExit(managedPid);
      }

      await _clearManagedProcessState();
      await _cancelProcessOutput();
      unawaited(_upnpService.shutdown());
      return true;
    } catch (e, stackTrace) {
      this.e(
        'Failed to stop built-in Aria2 instance',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool isRunning() {
    return _aria2Process != null || _managedPid != null;
  }

  Future<bool> _adoptPersistedProcess() async {
    final pid = await _readPersistedPid();
    if (pid == null) {
      return false;
    }
    if (!await ProcessLifecycleService.instance.isExpectedProcess(
      pid,
      _aria2cPath!,
    )) {
      await _deletePidFileIfMatches(pid);
      return false;
    }
    _managedPid = pid;
    await ProcessLifecycleService.instance.attachToAppLifecycle(pid);
    return true;
  }

  Future<bool> _isRpcReachable() async {
    final client = Aria2RpcClient(
      getBuiltinInstanceConfig(),
      requestTimeout: const Duration(seconds: 1),
      maximumAttempts: 1,
    );
    try {
      await client.getVersion();
      return true;
    } on UnauthorizedException {
      return true;
    } on ConnectionFailedException {
      return false;
    } catch (error, stackTrace) {
      w(
        'Failed to probe the built-in aria2 RPC endpoint',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      await client.close();
    }
  }

  /// Returns [preferred] when bindable, otherwise scans upward for the first
  /// free loopback port so the engine can recover from conflicts.
  @visibleForTesting
  Future<int> resolveAvailableRpcPort(
    int preferred, {
    int maxAttempts = 32,
  }) async {
    if (await _isTcpPortFree(preferred)) {
      return preferred;
    }
    for (var offset = 1; offset <= maxAttempts; offset++) {
      final candidate = preferred + offset;
      if (candidate > 65535) {
        break;
      }
      if (await _isTcpPortFree(candidate)) {
        return candidate;
      }
    }
    // Nothing free in the window: keep the configured port and let the
    // regular startup failure surface to the user.
    return preferred;
  }

  Future<bool> _isTcpPortFree(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  /// Best-effort persistence of a recovered RPC port so restarts keep
  /// working. Requires bound settings; disk fallbacks are intentionally not
  /// rewritten here.
  Future<void> _persistRpcPort(int port) async {
    final settings = _settings;
    if (settings == null || !settings.isLoaded) {
      w('Cannot persist recovered RPC port without loaded settings');
      return;
    }
    try {
      await settings.setRpcListenPort(port);
    } catch (e, stackTrace) {
      w(
        'Failed to persist recovered built-in RPC port $port',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<int?> _readPersistedPid() async {
    final pidFile = _pidFile;
    if (pidFile == null || !await pidFile.exists()) {
      return null;
    }
    try {
      final pid = int.tryParse((await pidFile.readAsString()).trim());
      if (pid == null || pid <= 0) {
        await pidFile.delete();
        return null;
      }
      return pid;
    } on FileSystemException catch (error, stackTrace) {
      w(
        'Failed to read the built-in aria2 PID file',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _persistManagedPid(int pid) async {
    final pidFile = _pidFile;
    if (pidFile == null) {
      return;
    }
    await AtomicFile.writeString(pidFile, '$pid\n');
  }

  Future<void> _deletePidFileIfMatches(int pid) async {
    final pidFile = _pidFile;
    if (pidFile == null || !await pidFile.exists()) {
      return;
    }
    try {
      final persistedPid = int.tryParse((await pidFile.readAsString()).trim());
      if (persistedPid == pid) {
        await pidFile.delete();
      }
    } on FileSystemException catch (error, stackTrace) {
      w(
        'Failed to delete the built-in aria2 PID file',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _waitForPidExit(int pid) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (!await ProcessLifecycleService.instance.isExpectedProcess(
        pid,
        _aria2cPath!,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('aria2 process $pid did not exit');
  }

  Future<void> _clearManagedProcessState() async {
    final pid = _managedPid;
    _aria2Process = null;
    _managedPid = null;
    _isConnected = false;
    _activeRpcPort = null;
    if (pid != null) {
      await _deletePidFileIfMatches(pid);
    }
  }

  Future<void> _shutdownThroughRpcIfPossible() async {
    final client = Aria2RpcClient(getBuiltinInstanceConfig());
    try {
      await client.saveSession().timeout(_rpcShutdownTimeout);
      await client.shutdown(force: true).timeout(_rpcShutdownTimeout);
    } on TimeoutException {
      w(
        'Timed out during built-in Aria2 RPC shutdown; falling back to process termination',
      );
      _aria2Process?.kill();
    } catch (e, stackTrace) {
      w(
        'Failed to stop built-in Aria2 through RPC; falling back to process termination',
        error: e,
        stackTrace: stackTrace,
      );
      _aria2Process?.kill();
    } finally {
      await client.close();
    }
  }

  void _monitorProcessOutput(Process process) {
    _stdoutSubscription = process.stdout.transform(utf8.decoder).listen((_) {});

    _stderrSubscription = process.stderr.transform(utf8.decoder).listen((data) {
      if (!_isConnected) {
        e('Aria2 [builtin] stderr: $data');
      }
    });
  }

  Future<void> _cancelProcessOutput() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
  }

  void onConnected() {
    _isConnected = true;
    _lastStartError = null;
    clearPendingApply();
    unawaited(syncUpnpStateForRunningInstance());
  }

  Aria2Instance getBuiltinInstanceConfig() {
    final settings = _readSettingsSnapshot();
    return Aria2Instance(
      id: 'builtin',
      name: 'Built-in Instance',
      type: InstanceType.builtin,
      protocol: 'ws',
      host: '127.0.0.1',
      port: _activeRpcPort ?? _configuration.getRpcPort(settings),
      secret: _configuration.getRpcSecret(settings),
      downloadDir: _configuration.resolveConfiguredFilePath(
        settings['downloadDir'],
        getDefaultDownloadDirectorySync(),
      ),
      status: ConnectionStatus.disconnected,
    );
  }

  void dispose() {
    if (isRunning()) {
      unawaited(stopInstance());
    } else {
      _activeRpcPort = null;
    }
    clearPendingApply();
    _instance = null;
  }
}
