import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'models/settings.dart';
import 'services/protocol_integration_service.dart';
import 'services/startup_integration_service.dart';
import 'services/system_tray_service.dart';
import 'services/data_migration_service.dart';
import 'services/core_provisioning_service.dart';
import 'services/builtin_instance_service.dart';
import 'services/single_instance_service.dart';
import 'utils/app_paths.dart';
import 'utils/logging.dart';

void main(List<String> args) async {
  // Ensure all platform initializations are complete
  WidgetsFlutterBinding.ensureInitialized();
  initializeAppLogging();

  final singleInstanceService = SingleInstanceService.instance;
  final singleInstanceResult = await singleInstanceService.acquire();
  switch (singleInstanceResult) {
    case SingleInstanceAcquireResult.acquired:
      await _initializeApplication(args, singleInstanceService);
    case SingleInstanceAcquireResult.existingInstanceActivated:
      return;
    case SingleInstanceAcquireResult.unconfirmedConflict:
      final logger = taggedLogger('Main');
      logger.e('Unable to confirm ownership of the single-instance server');
      runApp(
        _SingleInstanceStartupErrorApp(
          onRetry: () async {
            final retryResult = await singleInstanceService.acquire();
            switch (retryResult) {
              case SingleInstanceAcquireResult.acquired:
                await _initializeApplication(args, singleInstanceService);
              case SingleInstanceAcquireResult.existingInstanceActivated:
                exit(0);
              case SingleInstanceAcquireResult.unconfirmedConflict:
                throw StateError(
                  'Unable to confirm ownership of the single-instance server',
                );
            }
          },
        ),
      );
  }
}

Future<void> _initializeApplication(
  List<String> args,
  SingleInstanceService singleInstanceService,
) async {
  await AppPaths.initialize();

  final logger = taggedLogger('Main');
  try {
    await DataMigrationService().migrateLegacyPortableData();
  } catch (e, stackTrace) {
    logger.e(
      'Failed to migrate legacy application data',
      error: e,
      stackTrace: stackTrace,
    );
  }
  try {
    await CoreProvisioningService().ensureDefaultConfiguration();
  } catch (e, stackTrace) {
    logger.e(
      'Failed to provision the built-in aria2 configuration',
      error: e,
      stackTrace: stackTrace,
    );
  }

  ProtocolIntegrationService().captureInitialArguments(args);

  final settings = Settings();
  await settings.loadSettings();
  BuiltinInstanceService().bindSettings(settings);
  try {
    await StartupIntegrationService.instance.initialize();
  } catch (e, stackTrace) {
    logger.e(
      'Failed to initialize run-at-startup integration',
      error: e,
      stackTrace: stackTrace,
    );
  }

  // Initialize window manager
  await WindowManagerService().initialize(hideTitleBar: settings.hideTitleBar);
  singleInstanceService.setOnActivate(() async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Run the application
  runApp(MyApp(initialSettings: settings));
}

class _SingleInstanceStartupErrorApp extends StatefulWidget {
  const _SingleInstanceStartupErrorApp({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<_SingleInstanceStartupErrorApp> createState() =>
      _SingleInstanceStartupErrorAppState();
}

class _SingleInstanceStartupErrorAppState
    extends State<_SingleInstanceStartupErrorApp> {
  bool _isRetrying = false;
  String? _retryError;

  Future<void> _retry() async {
    if (_isRetrying) {
      return;
    }

    setState(() {
      _isRetrying = true;
      _retryError = null;
    });
    try {
      await widget.onRetry();
    } catch (error, stackTrace) {
      taggedLogger('Main').e(
        'Retrying single-instance startup failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _retryError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Setsuna',
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Setsuna could not start',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Setsuna could not confirm that it owns its single-instance '
                      'server. Close any conflicting process and try again.',
                    ),
                    if (_retryError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _retryError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isRetrying ? null : _retry,
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
