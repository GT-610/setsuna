import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setsuna/generated/l10n/l10n.dart';
import 'package:setsuna/pages/download_page/components/filter_selector.dart';
import 'package:setsuna/pages/download_page/components/task_list_item.dart';
import 'package:setsuna/pages/download_page/components/task_toolbar.dart';
import 'package:setsuna/pages/download_page/enums.dart';
import 'package:setsuna/pages/download_page/models/download_task.dart';

void main() {
  Widget buildLocalized(Widget child, {double width = 800}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );
  }

  testWidgets('desktop task toolbar fits the minimum content width', (
    tester,
  ) async {
    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    addTearDown(searchController.dispose);
    addTearDown(searchFocusNode.dispose);

    await tester.pumpWidget(
      buildLocalized(
        TaskToolbar(
          onAddTask: () {},
          onPauseAll: () {},
          onResumeAll: () {},
          onDeleteAll: () {},
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          onSearchChanged: (_) {},
          sortOption: TaskSortOption.name,
          sortDescending: false,
          onSortChanged: (_) {},
          onSortDirectionChanged: (_) {},
        ),
        width: 592,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('task-search-field')), findsOneWidget);
  });

  testWidgets('desktop filter sidebar selects a status filter', (tester) async {
    CategoryType? selectedCategory;
    FilterOption? selectedFilter;

    await tester.pumpWidget(
      buildLocalized(
        FilterSelector(
          currentCategoryType: CategoryType.all,
          selectedFilter: FilterOption.all,
          selectedInstanceId: null,
          instanceNames: const {'remote': 'Home server'},
          instanceIds: const ['remote'],
          onCategoryChanged: (value) => selectedCategory = value,
          onFilterChanged: (value) => selectedFilter = value,
          onInstanceSelected: (_) {},
        ),
        width: 190,
      ),
    );

    await tester.tap(find.text('Downloading'));

    expect(selectedCategory, CategoryType.byStatus);
    expect(selectedFilter, FilterOption.active);
  });

  testWidgets('compact task row exposes desktop selection control', (
    tester,
  ) async {
    var selected = false;
    final task = DownloadTask(
      id: 'gid',
      name: 'linux-distribution.iso',
      status: DownloadStatus.active,
      progress: 0.42,
      downloadSpeed: '12 MiB/s',
      uploadSpeed: '0 B/s',
      size: '4 GiB',
      completedSize: '1.7 GiB',
      isLocal: true,
      instanceId: 'builtin',
    );

    await tester.pumpWidget(
      buildLocalized(
        TaskListItem(
          task: task,
          instanceNames: const {'builtin': 'Built-in'},
          onTap: () {},
          onSelectionToggle: () => selected = true,
          onTaskUpdated: () {},
          onOpenDirectory: (_) {},
        ),
        width: 400,
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Checkbox));
    expect(selected, isTrue);
  });
}
