import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/app_paths.dart';
import '../utils/default_download_directory.dart';
import '../utils/logging.dart';
import '../utils/speed_schedule.dart';

/// Resolves persisted options and builds the arguments used to start aria2.
class BuiltinEngineConfiguration with Loggable {
  BuiltinEngineConfiguration(Map<String, dynamic> settings, this.paths)
    : settings = Map.unmodifiable(settings);
  final Map<String, dynamic> settings;
  final AppPaths paths;
  int getRpcPort([Map<String, dynamic>? settings]) {
    final s = settings ?? this.settings;
    final rawPort = s['rpcListenPort'];
    final port = rawPort is int
        ? rawPort
        : int.tryParse(rawPort?.toString().trim() ?? '');
    return port != null && port >= 1 && port <= 65535 ? port : 16800;
  }

  String getRpcSecret([Map<String, dynamic>? settings]) {
    final s = settings ?? this.settings;
    final secret = s['rpcSecret'];
    return secret is String ? secret : '';
  }

  String _defaultSessionPath() {
    return p.join(paths.coreDirectory.path, 'aria2.session');
  }

  String _defaultLogPath() {
    return p.join(paths.logDirectory.path, 'aria2.log');
  }

  String _defaultDownloadDir() {
    return getDefaultDownloadDirectorySync();
  }

  String resolveEffectiveBtListenPort(Map<String, dynamic> settings) {
    final raw = settings['btListenPort'];
    final configuredPort = (raw is String ? raw : '').trim();
    return configuredPort.isNotEmpty ? configuredPort : '6881-6999';
  }

  int resolveEffectiveDhtListenPort(Map<String, dynamic> settings) {
    final rawValue = settings['dhtListenPort'];
    if (rawValue is int && rawValue >= 1 && rawValue <= 65535) {
      return rawValue;
    }
    if (rawValue is String) {
      final parsed = int.tryParse(rawValue.trim());
      if (parsed != null && parsed >= 1 && parsed <= 65535) {
        return parsed;
      }
    }
    return 26701;
  }

  String getSessionPath(Map<String, dynamic> settings) {
    return resolveConfiguredFilePath(
      settings['sessionPath'],
      _defaultSessionPath(),
    );
  }

  String resolveConfiguredFilePath(dynamic rawValue, String fallbackPath) {
    final configuredPath = (rawValue is String ? rawValue : '').trim();
    return configuredPath.isNotEmpty ? configuredPath : fallbackPath;
  }

  void _ensureParentDirectoryExists(String filePath) {
    final directory = File(filePath).parent;
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  String formatSpeedLimitArg(dynamic rawValue) {
    final value = rawValue is num
        ? rawValue.toInt()
        : int.tryParse(rawValue?.toString() ?? '') ?? 0;
    return value > 0 ? '${value}K' : '0';
  }

  /// Computes the effective overall limit (KB/s, 0 = unlimited) from a
  /// settings snapshot, honoring the master switch and the schedule window.
  int effectiveSpeedLimitValueFromSnapshot(
    Map<String, dynamic> settings,
    String key, [
    DateTime? now,
  ]) {
    final raw = settings[key];
    final configured = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 0;
    final enabledRaw = settings['speedLimitEnabled'];
    final limitsEnabled = enabledRaw is bool ? enabledRaw : true;
    final scheduleDaysRaw = settings['speedScheduleDays'];
    final startRaw = settings['speedScheduleStartMinutes'];
    final endRaw = settings['speedScheduleEndMinutes'];
    final windowActive = isWithinSpeedScheduleWindow(
      scheduleEnabled: settings['speedScheduleEnabled'] == true,
      daysBitmask: scheduleDaysRaw is int ? scheduleDaysRaw : allDaysBitmask,
      startMinutes: startRaw is int ? startRaw : 0,
      endMinutes: endRaw is int ? endRaw : minutesPerDay,
      now: now ?? DateTime.now(),
    );
    return effectiveSpeedLimit(
      limitsEnabled: limitsEnabled,
      windowActive: windowActive,
      configuredValue: configured,
    );
  }

  String _effectiveSpeedLimitArg(Map<String, dynamic> settings, String key) {
    return formatSpeedLimitArg(
      effectiveSpeedLimitValueFromSnapshot(settings, key),
    );
  }

  int effectiveSeedTime(bool keepSeeding, dynamic rawValue) {
    if (keepSeeding) {
      return 525600;
    }

    return rawValue is num
        ? rawValue.toInt()
        : int.tryParse(rawValue?.toString() ?? '') ?? 60;
  }

  double effectiveSeedRatio(bool keepSeeding, dynamic rawValue) {
    if (keepSeeding) {
      return 0.0;
    }

    return rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '') ?? 1.0;
  }

  /// aria2 only accepts HTTP proxies for --all-proxy and crashes on SOCKS
  /// schemes; returns null for unsupported values.
  static String? sanitizeAllProxyArg(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return null;
    }
    final scheme = Uri.tryParse(value)?.scheme.toLowerCase() ?? '';
    if (scheme.startsWith('socks')) {
      return null;
    }
    return value;
  }

  /// Removes inherited proxy environment variables so host-level proxies
  /// never leak into the bundled engine.
  static Map<String, String> sanitizedEngineEnvironment(
    Map<String, String> base,
  ) {
    const blockedNames = <String>{
      'http_proxy',
      'https_proxy',
      'ftp_proxy',
      'all_proxy',
      'no_proxy',
    };
    final env = <String, String>{};
    base.forEach((name, value) {
      if (blockedNames.contains(name.toLowerCase())) {
        return;
      }
      env[name] = value;
    });
    // Explicit empty overrides: aria2 treats empty proxy env vars as "no
    // proxy", which also defeats platform-level environment merging.
    for (final name in blockedNames) {
      env[name] = '';
    }
    return env;
  }

  String _recoveryFilePath(String filePath, int rpcPort) {
    final extension = p.extension(filePath);
    final basename = p.basenameWithoutExtension(filePath);
    return p.join(p.dirname(filePath), '$basename.recovery-$rpcPort$extension');
  }

  List<String> buildArguments({
    required bool detachShareOnly,
    int? rpcPortOverride,
    bool useRecoveryPaths = false,
  }) {
    final settings = this.settings;
    final rpcPort = rpcPortOverride ?? getRpcPort(settings);
    final rpcSecret = getRpcSecret(settings);
    final keepSeeding = settings['keepSeeding'] == true;
    final seedTime = effectiveSeedTime(keepSeeding, settings['seedTime']);
    final seedRatio = effectiveSeedRatio(keepSeeding, settings['seedRatio']);
    final btListenPort = resolveEffectiveBtListenPort(settings);
    final configuredSessionPath = getSessionPath(settings);
    final configuredLogPath = resolveConfiguredFilePath(
      settings['logPath'],
      _defaultLogPath(),
    );
    final sessionPath = useRecoveryPaths
        ? _recoveryFilePath(configuredSessionPath, rpcPort)
        : configuredSessionPath;
    final logPath = useRecoveryPaths
        ? _recoveryFilePath(configuredLogPath, rpcPort)
        : configuredLogPath;
    final downloadDir = resolveConfiguredFilePath(
      settings['downloadDir'],
      _defaultDownloadDir(),
    );

    _ensureParentDirectoryExists(sessionPath);
    _ensureParentDirectoryExists(logPath);
    Directory(downloadDir).createSync(recursive: true);

    final args = <String>[
      '--enable-rpc',
      '--rpc-listen-all=false',
      '--rpc-allow-origin-all',
      '--rpc-listen-port=$rpcPort',
      '--rpc-save-upload-metadata=true',
      '--rpc-max-request-size=10M',
      '--continue=${settings['continueDownloads'] ?? true}',
      '--max-concurrent-downloads=${settings['maxConcurrentDownloads'] ?? 5}',
      '--max-connection-per-server=${settings['maxConnectionPerServer'] ?? 16}',
      '--min-split-size=10M',
      '--split=${settings['split'] ?? 16}',
      '--max-overall-download-limit=${_effectiveSpeedLimitArg(settings, 'maxOverallDownloadLimit')}',
      '--max-overall-upload-limit=${_effectiveSpeedLimitArg(settings, 'maxOverallUploadLimit')}',
      '--max-download-limit=0',
      '--max-upload-limit=0',
      '--file-allocation=prealloc',
      '--disk-cache=64M',
      '--dir=$downloadDir',
      '--allow-overwrite=${settings['allowOverwrite'] ?? false}',
      '--allow-piece-length-change=true',
      '--auto-file-renaming=${settings['autoFileRenaming'] ?? true}',
      '--check-integrity=true',
      '--remote-time=true',
      '--follow-torrent=mem',
      '--seed-time=$seedTime',
      '--seed-ratio=$seedRatio',
      // Keep seeding tasks from occupying concurrent-download slots
      // (aria2-next only; gated by an engine version probe at startup).
      if (detachShareOnly) '--detach-share-only=true',
      '--bt-enable-lpd=true',
      '--bt-max-peers=100',
      '--bt-require-crypto=${settings['btForceEncryption'] ?? false}',
      '--bt-save-metadata=${settings['btSaveMetadata'] ?? true}',
      '--bt-load-saved-metadata=${settings['btLoadSavedMetadata'] ?? true}',
      '--listen-port=$btListenPort',
      '--dht-listen-port=${resolveEffectiveDhtListenPort(settings)}',
      '--enable-dht6=${settings['enableDht6'] ?? true}',
      '--conf-path=${p.join(paths.coreDirectory.path, 'aria2.conf')}',
      '--save-session=$sessionPath',
      '--save-session-interval=30',
      '--force-save=false',
      '--log-level=info',
      '--log=$logPath',
    ];

    final allProxy = settings['allProxy'] as String? ?? '';
    final noProxy = settings['noProxy'] as String? ?? '';
    final proxyEnabled = settings['proxyEnabled'] == true;
    final userAgent = settings['userAgent'] as String? ?? '';
    final btTracker = settings['btTracker'] as String? ?? '';
    final btExcludeTracker = settings['btExcludeTracker'] as String? ?? '';

    if (rpcSecret.isNotEmpty) {
      args.add('--rpc-secret=$rpcSecret');
    }
    if (proxyEnabled && allProxy.isNotEmpty) {
      final sanitizedProxy = sanitizeAllProxyArg(allProxy);
      if (sanitizedProxy != null) {
        args.add('--all-proxy=$sanitizedProxy');
      } else {
        w(
          'Ignored the configured --all-proxy value because SOCKS proxies are '
          'not supported by aria2 and crash the engine',
        );
      }
    }
    if (proxyEnabled && noProxy.isNotEmpty) {
      args.add('--no-proxy=$noProxy');
    }
    if (userAgent.isNotEmpty) {
      args.add('--user-agent=$userAgent');
    }
    if (btTracker.isNotEmpty) {
      args.add('--bt-tracker=$btTracker');
    }
    if (btExcludeTracker.isNotEmpty) {
      args.add('--bt-exclude-tracker=$btExcludeTracker');
    }
    if (File(sessionPath).existsSync()) {
      args.add('--input-file=$sessionPath');
    }

    return args;
  }
}
