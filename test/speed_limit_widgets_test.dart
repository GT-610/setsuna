import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:setsuna/generated/l10n/l10n.dart';
import 'package:setsuna/models/settings.dart';
import 'package:setsuna/pages/components/quick_speed_limit_dialog.dart';
import 'package:setsuna/pages/settings_page/components/speed_limit_card.dart';
import 'support/memory_settings_repository.dart';
import 'support/settings_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SpeedLimitCard', () {
    late Settings settings;

    setUp(() async {
      settings = Settings(
        repository: MemorySettingsRepository(<String, dynamic>{}),
      );
      await settings.loadSettings();
      addTearDown(settings.dispose);
    });

    Future<AppLocalizations> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(
        settingsTestApp(
          settings,
          Consumer<Settings>(
            builder: (context, value, child) => SpeedLimitCard(settings: value),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return testL10n(tester);
    }

    testWidgets('toggling the master switch persists the setting', (
      tester,
    ) async {
      final l10n = await pumpCard(tester);

      expect(settings.speedLimitEnabled, isTrue);
      expect(find.text(l10n.maxOverallUploadSpeed), findsOneWidget);

      final masterTile = find.widgetWithText(
        ListTile,
        l10n.speedLimitEnabledTitle,
      );
      await tester.tap(
        find.descendant(of: masterTile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(settings.speedLimitEnabled, isFalse);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, l10n.maxOverallUploadSpeed),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('uses settings tiles and edits a limit in a dialog', (
      tester,
    ) async {
      final l10n = await pumpCard(tester);

      expect(find.text(l10n.maxOverallUploadSpeed), findsOneWidget);
      expect(find.text(l10n.maxOverallDownloadSpeed), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text(l10n.maxOverallUploadSpeed));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), '512');
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      expect(settings.maxOverallUploadLimit, 512);
      expect(
        find.textContaining('${settings.maxOverallUploadLimit}'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Quick speed-limit dialog', () {
    late ControlledSettingsRepository repository;
    late Settings settings;

    setUp(() async {
      repository = ControlledSettingsRepository();
      settings = Settings(repository: repository);
      await settings.loadSettings();
      addTearDown(settings.dispose);
    });

    testWidgets('uses global labels and guards an in-progress save', (
      tester,
    ) async {
      await tester.pumpWidget(
        settingsTestApp(settings, dialogLauncher(showQuickSpeedLimitDialog)),
      );
      await tester.pumpAndSettle();
      final l10n = testL10n(tester);

      await tester.tap(find.byKey(DIALOG_LAUNCHER_KEY));
      await tester.pumpAndSettle();
      expect(find.text(l10n.maxOverallDownloadSpeed), findsOneWidget);
      expect(find.text(l10n.maxOverallUploadSpeed), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '256');
      await tester.enterText(find.byType(TextField).last, '128');
      repository.pendingSave = Completer<void>();
      final saveFinder = find.widgetWithText(FilledButton, l10n.save);
      final save = tester.widget<FilledButton>(saveFinder).onPressed!;
      save();
      save();
      await tester.pump();

      expect(tester.widget<FilledButton>(saveFinder).onPressed, isNull);
      final callsDuringFirstSave = repository.saveCalls;
      expect(callsDuringFirstSave, greaterThan(0));

      repository.pendingSave!.complete();
      await tester.pumpAndSettle();

      expect(repository.saveCalls, callsDuringFirstSave + 1);
      expect(settings.maxOverallDownloadLimit, 256);
      expect(settings.maxOverallUploadLimit, 128);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('reports persistence failures and leaves the dialog open', (
      tester,
    ) async {
      await tester.pumpWidget(
        settingsTestApp(settings, dialogLauncher(showQuickSpeedLimitDialog)),
      );
      await tester.pumpAndSettle();
      final l10n = testL10n(tester);

      await tester.tap(find.byKey(DIALOG_LAUNCHER_KEY));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '256');
      repository.nextSaveError = StateError('save failed');
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(l10n.saveSettingsFailed), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, l10n.save))
            .onPressed,
        isNotNull,
      );
    });
  });
}
