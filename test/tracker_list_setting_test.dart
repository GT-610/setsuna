import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/generated/l10n/l10n.dart';
import 'package:setsuna/pages/components/tracker_list_setting.dart';

void main() {
  testWidgets('adds, removes and refreshes serialized tracker entries', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'udp://one,https://two');
    addTearDown(controller.dispose);
    String? changed;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TrackerListSetting(
            title: 'Trackers',
            controller: controller,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );
    expect(find.text('udp://one'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'https://three\r\nudp://one, udp://four',
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    expect(changed, 'udp://one,https://two,https://three,udp://four');
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pump();
    expect(controller.text, 'https://two,https://three,udp://four');
    controller.text = 'udp://synced';
    await tester.pump();
    expect(find.text('udp://synced'), findsOneWidget);
    expect(find.text('https://two'), findsNothing);
  });
  testWidgets('disabled tracker lists prevent input, additions and deletions', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'udp://one');
    addTearDown(controller.dispose);
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TrackerListSetting(
                title: 'Trackers',
                controller: controller,
                enabled: enabled,
              );
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'udp://two');
    update(() => enabled = false);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Add'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Delete'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.tap(find.byTooltip('Delete'));
    expect(controller.text, 'udp://one');
    update(() => enabled = true);
    await tester.pump();
    await tester.tap(find.byTooltip('Add'));
    expect(controller.text, 'udp://one,udp://two');
  });
}
