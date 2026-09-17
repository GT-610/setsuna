import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/pages/download_page/enums.dart';
import 'package:setsuna/pages/download_page/models/download_task.dart';

void main() {
  group('DownloadTask', () {
    group('key', () {
      test('returns instanceId::id', () {
        final task = DownloadTask(
          id: 'task-123',
          name: 'file.zip',
          status: DownloadStatus.active,
          progress: 0.5,
          downloadSpeed: '100 KB/s',
          uploadSpeed: '10 KB/s',
          size: '1.00 GB',
          completedSize: '500.00 MB',
          isLocal: true,
          instanceId: 'inst-1',
        );

        expect(task.key, 'inst-1::task-123');
      });

      test('different instances produce different keys', () {
        final task1 = DownloadTask(
          id: 'task-1',
          name: 'file.zip',
          status: DownloadStatus.active,
          progress: 0,
          downloadSpeed: '0 B/s',
          uploadSpeed: '0 B/s',
          size: '0 B',
          completedSize: '0 B',
          isLocal: true,
          instanceId: 'inst-1',
        );

        final task2 = DownloadTask(
          id: 'task-1',
          name: 'file.zip',
          status: DownloadStatus.active,
          progress: 0,
          downloadSpeed: '0 B/s',
          uploadSpeed: '0 B/s',
          size: '0 B',
          completedSize: '0 B',
          isLocal: true,
          instanceId: 'inst-2',
        );

        expect(task1.key, isNot(task2.key));
      });
    });
  });
}
