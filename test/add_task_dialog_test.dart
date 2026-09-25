import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/generated/l10n/l10n.dart';
import 'package:setsuna/models/aria2_instance.dart';
import 'package:setsuna/pages/download_page/components/add_task_dialog.dart';

void main() {
  testWidgets('submits lines separately and retries only remaining links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final submitted = <String>[];
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AddTaskDialog(
                  targetInstances: [
                    Aria2Instance(
                      id: 'local',
                      name: 'Local',
                      type: InstanceType.builtin,
                      protocol: 'http',
                      host: 'localhost',
                      port: 6800,
                    ),
                  ],
                  defaultTargetInstanceId: 'local',
                  initialUri:
                      ' https://example.com/a \r\n\r\nhttps://example.com/b\nhttps://example.com/c ',
                  initialShowDownloadsAfterAdd: false,
                  onAddTask:
                      (type, uri, dir, content, target, options, show) async {
                        submitted.add(uri);
                        return !(fail && uri.endsWith('/b'));
                      },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(submitted, ['https://example.com/a', 'https://example.com/b']);
    expect(find.byType(AddTaskDialog), findsOneWidget);
    fail = false;
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(submitted, [
      'https://example.com/a',
      'https://example.com/b',
      'https://example.com/b',
      'https://example.com/c',
    ]);
    expect(find.byType(AddTaskDialog), findsNothing);
  });
}
