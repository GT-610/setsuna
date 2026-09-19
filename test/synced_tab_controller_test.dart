import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setsuna/utils/app_motion.dart';
import 'package:setsuna/widgets/synced_tab_controller.dart';

void main() {
  testWidgets(
    'SyncedTabScope exposes a SyncedTabController with shared motion',
    (tester) async {
      late TabController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: SyncedTabScope(
            tabCount: 3,
            builder: (context, value) {
              controller = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(controller, isA<SyncedTabController>());
      expect(controller.animationDuration, kPageTransitionDuration);
    },
  );

  testWidgets(
    'SyncedTabScope keeps TabBar/TabBarView valid when tabCount grows',
    (tester) async {
      var tabCount = 2;

      Widget build() {
        return MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: SyncedTabScope(
                  tabCount: tabCount,
                  builder: (context, controller) {
                    return Column(
                      children: [
                        TabBar(
                          controller: controller,
                          tabs: [
                            for (var i = 0; i < tabCount; i++)
                              Tab(text: 'tab$i'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: controller,
                            children: [
                              for (var i = 0; i < tabCount; i++)
                                Center(child: Text('body$i')),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => tabCount = 4),
                          child: const Text('grow'),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(build());
      expect(find.text('body0'), findsOneWidget);

      await tester.tap(find.text('grow'));
      await tester.pumpAndSettle();

      // A stale controller (not rebuilt on the count change) would trip a
      // TabBar length assertion here.
      expect(tester.takeException(), isNull);
      expect(find.text('tab3'), findsOneWidget);
      expect(find.text('body0'), findsOneWidget);
    },
  );
}
