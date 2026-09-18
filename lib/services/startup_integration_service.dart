import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../constants/app_branding.dart';
import '../models/settings.dart';
import '../utils/logging.dart';

class StartupIntegrationService with Loggable {
  StartupIntegrationService({LaunchAtStartup? launcher})
    : _launcher = launcher ?? launchAtStartup;
  static final instance = StartupIntegrationService();
  final LaunchAtStartup _launcher;
  bool _isSetup = false;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> initialize() async {
    if (_isSetup || !isSupported) {
      return;
    }

    _launcher.setup(
      appName: kAppName,
      appPath: Platform.resolvedExecutable,
      packageName: kAppPackageName,
    );
    _isSetup = true;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) {
      return;
    }

    await initialize();
    final currentlyEnabled = await _launcher.isEnabled();
    if (currentlyEnabled == enabled) {
      return;
    }

    if (enabled) {
      if (!await _launcher.enable()) {
        throw StateError('Failed to enable run-at-startup');
      }
      i('Run-at-startup enabled');
      return;
    }

    if (!await _launcher.disable()) {
      throw StateError('Failed to disable run-at-startup');
    }
    i('Run-at-startup disabled');
  }

  Future<void> reconcileStartupPreference(Settings settings) async {
    if (!isSupported) {
      return;
    }

    await initialize();
    await setEnabled(settings.autoStart);
  }
}
