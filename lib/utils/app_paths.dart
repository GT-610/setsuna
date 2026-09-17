import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_branding.dart';

class AppPaths {
  AppPaths({
    required this.supportDirectory,
    required this.legacyPortableDirectory,
    required this.bundledCoreDirectory,
  });

  static AppPaths? _instance;

  final Directory supportDirectory;
  final Directory legacyPortableDirectory;
  final Directory bundledCoreDirectory;

  Directory get configDirectory =>
      Directory(p.join(supportDirectory.path, 'config'));
  Directory get coreDirectory =>
      Directory(p.join(supportDirectory.path, 'core'));
  Directory get logDirectory =>
      Directory(p.join(supportDirectory.path, 'logs'));
  File get migrationMarker =>
      File(p.join(supportDirectory.path, '.migration-v1-complete'));

  static AppPaths get instance {
    final value = _instance;
    if (value != null) {
      return value;
    }
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final portableDirectory = Directory(
      p.join(executableDirectory.path, 'data'),
    );
    return _instance = AppPaths(
      supportDirectory: portableDirectory,
      legacyPortableDirectory: portableDirectory,
      bundledCoreDirectory: bundledCoreDirectoryFor(
        executableDirectory: executableDirectory,
        isMacOS: Platform.isMacOS,
      ),
    );
  }

  static Future<AppPaths> initialize() async {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }

    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final legacyPortableDirectory = Directory(
      p.join(executableDirectory.path, 'data'),
    );
    final platformSupportDirectory = await getApplicationSupportDirectory();
    final supportDirectory = Platform.isLinux
        ? Directory(p.join(platformSupportDirectory.path, kAppPackageName))
        : platformSupportDirectory;

    final paths = AppPaths(
      supportDirectory: supportDirectory,
      legacyPortableDirectory: legacyPortableDirectory,
      bundledCoreDirectory: bundledCoreDirectoryFor(
        executableDirectory: executableDirectory,
        isMacOS: Platform.isMacOS,
      ),
    );
    await paths.ensureDirectories();
    _instance = paths;
    return paths;
  }

  Future<void> ensureDirectories() async {
    for (final directory in <Directory>[
      supportDirectory,
      configDirectory,
      coreDirectory,
      logDirectory,
    ]) {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }
  }

  static Directory bundledCoreDirectoryFor({
    required Directory executableDirectory,
    required bool isMacOS,
  }) {
    final dataDirectory = isMacOS
        ? p.join(executableDirectory.path, '..', 'Resources', 'data')
        : p.join(executableDirectory.path, 'data');
    return Directory(p.normalize(p.join(dataDirectory, 'core')));
  }
}
