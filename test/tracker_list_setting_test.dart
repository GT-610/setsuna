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
}
