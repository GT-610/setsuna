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

    test(
      'deletes a directory symlink without following it',
      () async {
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
        await link.create(outsideDir.path);
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
      },
      skip: Platform.isWindows
          ? 'Creating symlinks commonly requires extra Windows privileges.'
          : false,
    );
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
}
