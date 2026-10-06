import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setsuna/generated/l10n/l10n.dart';
import 'package:setsuna/pages/download_page/components/directory_picker.dart';

void main() {
  const initialDirectory = r'C:\Users\Admin\Downloads';

  /// Runs [body] with the desktop platform selected.
  ///
  /// Desktop single-line fields select all of their content when focused, so
  /// this is the platform where the select-all regression reproduced. The
  /// override is restored in a `finally` because the test binding verifies that
  /// foundation debug variables are unset before teardown callbacks run.
  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    required String initialDirectory,
    ValueChanged<String>? onDirectoryChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DirectoryPicker(
            initialDirectory: initialDirectory,
            onDirectoryChanged: onDirectoryChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  TextEditingController controllerOf(WidgetTester tester) {
    return tester.widget<TextField>(find.byType(TextField)).controller!;
  }

  testWidgets('typing does not select the whole path', (tester) async {
    await onDesktop(() async {
      final changes = <String>[];
      await pumpPicker(
        tester,
        initialDirectory: initialDirectory,
        onDirectoryChanged: changes.add,
      );

      final finder = find.byType(TextField);
      await tester.tap(finder);
      await tester.pumpAndSettle();

      final controller = controllerOf(tester);
      expect(controller.selection.isValid, isTrue);
      expect(controller.selection.isCollapsed, isTrue);

      // Type one character at the caret the user is actually editing with.
      await tester.enterText(finder, '${controller.text}x');
      await tester.pump();

      expect(controller.text, '${initialDirectory}x');
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: initialDirectory.length + 1),
        reason: 'the caret must stay put instead of selecting the whole path',
      );
      expect(changes.last, '${initialDirectory}x');
    });
  });

  testWidgets('repeated typing keeps the caret at the end', (tester) async {
    await onDesktop(() async {
      await pumpPicker(tester, initialDirectory: initialDirectory);

      final finder = find.byType(TextField);
      await tester.tap(finder);
      await tester.pumpAndSettle();

      final controller = controllerOf(tester);
      var expected = initialDirectory;
      for (final char in ['a', 'b', 'c']) {
        expected += char;
        await tester.enterText(finder, expected);
        await tester.pump();

        expect(controller.text, expected);
        expect(
          controller.selection,
          TextSelection.collapsed(offset: expected.length),
        );
      }
    });
  });

  testWidgets('external directory update places the caret at the end', (
    tester,
  ) async {
    await onDesktop(() async {
      await pumpPicker(tester, initialDirectory: initialDirectory);
      await pumpPicker(tester, initialDirectory: r'D:\Media\Incoming');

      final controller = controllerOf(tester);
      expect(controller.text, r'D:\Media\Incoming');
      expect(controller.selection.isValid, isTrue);
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: r'D:\Media\Incoming'.length),
      );
    });
  });

  testWidgets('rebuilding with the same directory preserves the caret', (
    tester,
  ) async {
    await onDesktop(() async {
      await pumpPicker(tester, initialDirectory: initialDirectory);

      final finder = find.byType(TextField);
      await tester.tap(finder);
      await tester.pumpAndSettle();

      // Simulate the user placing the caret mid-path, then a parent rebuild
      // that reports the same directory.
      final controller = controllerOf(tester);
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();

      await pumpPicker(tester, initialDirectory: initialDirectory);

      expect(
        controllerOf(tester).selection,
        const TextSelection.collapsed(offset: 4),
      );
    });
  });
}
