import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setsuna/models/settings.dart';
import 'package:setsuna/pages/components/file_category_editor_dialog.dart';
import 'support/memory_settings_repository.dart';
import 'support/settings_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('File category editor', () {
    testWidgets('reports invalid rows and keeps the dialog open', (
      tester,
    ) async {
      final settings = Settings(
        repository: MemorySettingsRepository(<String, dynamic>{}),
      );
      await settings.loadSettings();
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        settingsTestApp(
          settings,
          dialogLauncher(
            (context) => showFileCategoryEditorDialog(context, settings),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = testL10n(tester);

      await tester.tap(find.byKey(DIALOG_LAUNCHER_KEY));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, l10n.fileCategoryAddRule),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.fileCategoryInvalidRule), findsOneWidget);
      expect(settings.fileCategoryRules, isEmpty);

      await tester.enterText(find.byType(TextField).first, '.MP4');
      await tester.enterText(find.byType(TextField).last, 'Videos/');
      await tester.pump();
      expect(find.text(l10n.fileCategoryInvalidRule), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(settings.fileCategoryRules.single.extensions, {'mp4'});
      expect(settings.fileCategoryRules.single.subdirectory, 'Videos');
    });

    testWidgets('reports persistence failures and keeps the dialog open', (
      tester,
    ) async {
      final repository = ControlledSettingsRepository();
      final settings = Settings(repository: repository);
      await settings.loadSettings();
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        settingsTestApp(
          settings,
          dialogLauncher(
            (context) => showFileCategoryEditorDialog(context, settings),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = testL10n(tester);

      await tester.tap(find.byKey(DIALOG_LAUNCHER_KEY));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, l10n.fileCategoryAddRule),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'mp4');
      await tester.enterText(find.byType(TextField).last, 'Videos');
      repository.nextSaveError = StateError('save failed');

      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.saveSettingsFailed), findsOneWidget);
      expect(settings.fileCategoryRules, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(settings.fileCategoryRules.single.subdirectory, 'Videos');
    });

    testWidgets('guards an in-progress category save', (tester) async {
      final repository = ControlledSettingsRepository();
      final settings = Settings(repository: repository);
      await settings.loadSettings();
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        settingsTestApp(
          settings,
          dialogLauncher(
            (context) => showFileCategoryEditorDialog(context, settings),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = testL10n(tester);
      await tester.tap(find.byKey(DIALOG_LAUNCHER_KEY));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, l10n.fileCategoryAddRule),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'mp4');
      await tester.enterText(find.byType(TextField).last, 'Videos');
      repository.pendingSave = Completer<void>();
      final callsBeforeSave = repository.saveCalls;
      final saveFinder = find.widgetWithText(FilledButton, l10n.save);
      final save = tester.widget<FilledButton>(saveFinder).onPressed!;

      save();
      save();
      await tester.pump();

      expect(repository.saveCalls, callsBeforeSave + 1);
      expect(tester.widget<FilledButton>(saveFinder).onPressed, isNull);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == l10n.delete,
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, l10n.fileCategoryAddRule),
            )
            .onPressed,
        isNull,
      );

      repository.pendingSave!.complete();
      await tester.pumpAndSettle();

      expect(repository.saveCalls, callsBeforeSave + 1);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
