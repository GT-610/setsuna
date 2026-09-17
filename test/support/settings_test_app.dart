import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:setsuna/generated/l10n/l10n.dart';
import 'package:setsuna/models/settings.dart';
import 'package:setsuna/services/instance_manager.dart';
import 'memory_settings_repository.dart';

const dialogLauncherKey = Key('dialogLauncher');

class ControlledSettingsRepository extends MemorySettingsRepository {
  ControlledSettingsRepository() : super(<String, dynamic>{});

  Completer<void>? pendingSave;
  Object? nextSaveError;
  int saveCalls = 0;

  @override
  Future<void> save(
    Map<String, dynamic> values, {
    bool credentialsBlocked = false,
  }) async {
    saveCalls++;
    final error = nextSaveError;
    nextSaveError = null;
    if (error != null) {
      throw error;
    }
    await pendingSave?.future;
    await super.save(values, credentialsBlocked: credentialsBlocked);
  }
}

Widget settingsTestApp(Settings settings, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<Settings>.value(value: settings),
      ChangeNotifierProvider<InstanceManager>(create: (_) => InstanceManager()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget dialogLauncher(void Function(BuildContext context) showDialog) {
  return Builder(
    builder: (context) => IconButton(
      key: dialogLauncherKey,
      onPressed: () => showDialog(context),
      icon: const Icon(Icons.open_in_new),
    ),
  );
}

AppLocalizations testL10n(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
}
