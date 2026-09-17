import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:setsuna/pages/download_page/enums.dart';
import 'package:setsuna/pages/download_page/models/download_task.dart';
import 'package:setsuna/pages/download_page/services/download_task_service.dart';
import 'package:setsuna/services/aria2_rpc_client.dart';

import 'support/fake_rpc_client.dart';

void main() {
  group('DownloadTaskService path safety', () {
    test(
      'skips deleting targets that resolve outside the base directory',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'download-task-service-',
        );
        addTearDown(() => tempRoot.deleteSync(recursive: true));

        final baseDir = Directory(p.join(tempRoot.path, 'base'))..createSync();
        final outsideDir = Directory(p.join(tempRoot.path, 'outside'))
          ..createSync();
        final outsideFile = File(p.join(outsideDir.path, 'escape.txt'))
          ..writeAsStringSync('keep me');

        final task = DownloadTask(
          id: 'task-1',
          name: 'ignored',
          status: DownloadStatus.stopped,
          progress: 0,
          downloadSpeed: '0 B/s',
          uploadSpeed: '0 B/s',
          size: '0 B',
          completedSize: '0 B',
          isLocal: true,
          instanceId: 'local',
          dir: baseDir.path,
          files: [
            {'path': p.join(baseDir.path, '..', 'outside', 'escape.txt')},
          ],
        );

        final errors = (await DownloadTaskService.deleteTaskWithClient(
          FakeRpcClient(),
          task,
          deleteDownloadedFiles: true,
        )).fileDeletionErrors;

        expect(outsideFile.existsSync(), isTrue);
        expect(
          errors.any(
            (error) => error.contains('Skipped path outside base directory'),
          ),
          isTrue,
        );
      },
    );

    test(
      'does not delete the base directory when task name is empty and files are missing',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'download-task-service-',
        );
        addTearDown(() => tempRoot.deleteSync(recursive: true));

        final baseDir = Directory(p.join(tempRoot.path, 'base'))..createSync();
        final preservedFile = File(p.join(baseDir.path, 'keep.txt'))
          ..writeAsStringSync('keep me');

        final task = DownloadTask(
          id: 'task-empty-name',
          name: '',
          status: DownloadStatus.stopped,
          progress: 0,
          downloadSpeed: '0 B/s',
          uploadSpeed: '0 B/s',
          size: '0 B',
          completedSize: '0 B',
          isLocal: true,
          instanceId: 'local',
          dir: baseDir.path,
          files: null,
        );

        final errors = (await DownloadTaskService.deleteTaskWithClient(
          FakeRpcClient(),
          task,
          deleteDownloadedFiles: true,
        )).fileDeletionErrors;

        expect(baseDir.existsSync(), isTrue);
        expect(preservedFile.existsSync(), isTrue);
        expect(
          errors,
          contains(
            'Skipped file deletion because task name is empty and no file list is available.',
          ),
        );
      },
    );

    test('deletes a directory symlink without following it', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'download-task-service-link-',
      );
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      final baseDir = Directory(p.join(tempRoot.path, 'base'))..createSync();
      final outsideDir = Directory(p.join(tempRoot.path, 'outside'))
        ..createSync();
      final outsideFile = File(p.join(outsideDir.path, 'keep.txt'))
        ..writeAsStringSync('keep me');
      final link = Link(p.join(baseDir.path, 'linked-directory'));
      await _directoryLink(link.path, outsideDir.path);
      final task = DownloadTask(
        id: 'task-link',
        name: 'linked-directory',
        status: DownloadStatus.stopped,
        progress: 0,
        downloadSpeed: '0 B/s',
        uploadSpeed: '0 B/s',
        size: '0 B',
        completedSize: '0 B',
        isLocal: true,
        instanceId: 'local',
        dir: baseDir.path,
        files: <Map<String, dynamic>>[
          <String, dynamic>{'path': link.path},
        ],
      );

      final errors = (await DownloadTaskService.deleteTaskWithClient(
        FakeRpcClient(),
        task,
        deleteDownloadedFiles: true,
      )).fileDeletionErrors;

      expect(errors, isEmpty);
      expect(await link.exists(), isFalse);
      expect(await outsideFile.exists(), isTrue);
    });
  });

  if (Platform.isWindows) {
    test(
      'handles Windows case variants and rejects unrelated UNC targets',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'setsuna-windows-path-',
        );
        addTearDown(() => root.delete(recursive: true));
        final file = File(p.join(root.path, 'Case.txt'));
        await file.writeAsString('remove');
        final result = await _deleteFile(
          root.path.toUpperCase(),
          file.path.toLowerCase(),
        );
        expect(result.fileDeletionErrors, isEmpty);
        expect(await file.exists(), isFalse);
        final unc = await _deleteFile(
          root.path,
          r'\\unrelated-host\share\keep.txt',
        );
        expect(unc.hasFileDeletionErrors, isTrue);
        expect(await root.exists(), isTrue);
      },
    );
  }

  test('recursive directory cleanup does not follow nested links', () async {
    final root = await Directory.systemTemp.createTemp('setsuna-nested-link-');
    addTearDown(() => root.delete(recursive: true));
    final base = await Directory(p.join(root.path, 'base')).create();
    final directory = await Directory(p.join(base.path, 'download')).create();
    final outside = await Directory(p.join(root.path, 'outside')).create();
    final keep = File(p.join(outside.path, 'keep.txt'));
    await keep.writeAsString('keep');
    await _directoryLink(p.join(directory.path, 'linked'), outside.path);
    final result = await _deleteFile(base.path, directory.path);
    expect(result.fileDeletionErrors, isEmpty);
    expect(await directory.exists(), isFalse);
    expect(await keep.readAsString(), 'keep');
  });
  test('does not delete files when task removal is unconfirmed', () async {
    final root = await Directory.systemTemp.createTemp('setsuna-delete-');
    addTearDown(() => root.delete(recursive: true));
    final file = File(p.join(root.path, 'keep.txt'));
    await file.writeAsString('keep');
    final task = DownloadTask(
      id: 'task',
      name: 'keep.txt',
      status: DownloadStatus.active,
      progress: 0,
      downloadSpeed: '0 B/s',
      uploadSpeed: '0 B/s',
      size: '0 B',
      completedSize: '0 B',
      isLocal: true,
      instanceId: 'builtin',
      dir: root.path,
    );
    final client = FakeRpcClient()
      ..remove = (_) async {
        throw const RpcResultIndeterminateException('aria2.remove');
      };
    await expectLater(
      DownloadTaskService.deleteTaskWithClient(
        client,
        task,
        deleteDownloadedFiles: true,
      ),
      throwsA(isA<RpcResultIndeterminateException>()),
    );
    expect(await file.readAsString(), 'keep');
  });
  test('rejects a file reached through an escaping parent link', () async {
    final root = await Directory.systemTemp.createTemp('setsuna-boundary-');
    addTearDown(() => root.delete(recursive: true));
    final base = await Directory(p.join(root.path, 'base')).create();
    final outside = await Directory(p.join(root.path, 'outside')).create();
    final file = File(p.join(outside.path, 'keep.txt'));
    await file.writeAsString('keep');
    final linkPath = p.join(base.path, 'linked');
    await _directoryLink(linkPath, outside.path);
    final result = await _deleteFile(base.path, p.join(linkPath, 'keep.txt'));
    expect(result.removedFromAria2, isTrue);
    expect(result.hasFileDeletionErrors, isTrue);
    expect(await file.readAsString(), 'keep');
  });

  test('supports a linked download root and removes empty parents', () async {
    final root = await Directory.systemTemp.createTemp('setsuna-linked-root-');
    addTearDown(() => root.delete(recursive: true));
    final real = await Directory(p.join(root.path, 'real')).create();
    final nested = await Directory(p.join(real.path, 'nested')).create();
    final file = File(p.join(nested.path, 'done.txt'));
    await file.writeAsString('done');
    final linkPath = p.join(root.path, 'downloads');
    await _directoryLink(linkPath, real.path);
    final result = await _deleteFile(
      linkPath,
      p.join(linkPath, 'nested', 'done.txt'),
    );
    expect(result.fileDeletionErrors, isEmpty);
    expect(await file.exists(), isFalse);
    expect(await nested.exists(), isFalse);
    expect(await real.exists(), isTrue);
  });

  test('preserves the root and adjacent prefix directories', () async {
    final root = await Directory.systemTemp.createTemp('setsuna-prefix-');
    addTearDown(() => root.delete(recursive: true));
    final base = await Directory(p.join(root.path, 'base')).create();
    final sibling = await Directory(p.join(root.path, 'base-other')).create();
    final file = File(p.join(sibling.path, 'keep.txt'));
    await file.writeAsString('keep');
    expect(
      (await _deleteFile(base.path, base.path)).hasFileDeletionErrors,
      isTrue,
    );
    expect(
      (await _deleteFile(base.path, file.path)).hasFileDeletionErrors,
      isTrue,
    );
    expect(await file.exists(), isTrue);
    expect(await base.exists(), isTrue);
    expect(
      (await _deleteFile(
        base.path,
        p.join(base.path, 'missing'),
      )).fileDeletionErrors,
      isEmpty,
    );
  });
}

Future<DeleteTaskResult> _deleteFile(String root, String path) {
  return DownloadTaskService.deleteTaskWithClient(
    FakeRpcClient(),
    DownloadTask(
      id: 'task',
      name: 'task',
      status: DownloadStatus.stopped,
      progress: 0,
      downloadSpeed: '0 B/s',
      uploadSpeed: '0 B/s',
      size: '0 B',
      completedSize: '0 B',
      isLocal: true,
      instanceId: 'builtin',
      dir: root,
      files: [
        {'path': path},
      ],
    ),
    deleteDownloadedFiles: true,
  );
}

Future<void> _directoryLink(String link, String target) async {
  if (!Platform.isWindows) {
    await Link(link).create(target);
    return;
  }
  String quote(String value) => "'${value.replaceAll("'", "''")}'";
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "New-Item -ItemType Junction -Path ${quote(link)} -Target ${quote(target)} -ErrorAction Stop | Out-Null",
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}
