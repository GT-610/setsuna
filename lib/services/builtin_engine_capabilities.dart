import 'dart:io';
import '../utils/logging.dart';

class BuiltinEngineCapabilities with Loggable {
  BuiltinEngineCapabilities({
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) : _runProcess = runProcess ?? Process.run;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;
  final Map<String, bool> _supported = {};

  /// The bundled engine is aria2-next; its detach-share-only option does not
  /// exist in vanilla aria2 (major version 1.x), which would refuse to start.
  Future<bool> supportsDetachShareOnly(String executable) async {
    final cached = _supported[executable];
    if (cached != null) {
      return cached;
    }
    try {
      final probe = _runProcess;
      final result = await probe(executable, const ['--version']);
      if (result.exitCode != 0) {
        w(
          'Bundled engine version probe exited with code ${result.exitCode}; '
          'assuming vanilla aria2 for this launch',
        );
        return false;
      }
      final match = RegExp(
        r'^aria2(?:-next)?(?:\s+version)?\s+(\d+)\.',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch('${result.stdout}${result.stderr}');
      final major = int.tryParse(match?.group(1) ?? '');
      if (major == null) {
        w(
          'Could not parse the bundled engine version; assuming vanilla '
          'aria2 for this launch',
        );
        return false;
      }
      _supported[executable] = major >= 2;
    } catch (e, stackTrace) {
      w(
        'Could not probe the bundled engine version; assuming vanilla aria2',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
    return _supported[executable]!;
  }
}
