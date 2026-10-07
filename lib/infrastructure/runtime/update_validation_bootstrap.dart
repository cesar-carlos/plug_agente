import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/installation_bundle_check.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/services/windows_privileged_updater.dart';
import 'package:plug_agente/infrastructure/services/windows_update_secrets_snapshot.dart';

/// Runs before regular DI, hub connection, schedules or startup actions.
/// The service supplies data only to the exact process it launched for this job.
Future<int> runUpdateValidation(List<String> args, AssetBundle bundle) async {
  AppDatabase? database;
  try {
    if (args.length != 3 ||
        args.first != '--update-validation' ||
        args.skip(1).any((value) => !RegExp(r'^[a-f0-9]{32}$').hasMatch(value))) {
      return 3;
    }
    final updater = WindowsPrivilegedUpdater();
    final contextResult = await updater.validationContext(args[1], args[2]);
    if (contextResult.isError()) return 3;
    final context = contextResult.getOrThrow();
    if (context['version'] != AppConstants.appVersion) return 3;
    final expectedDirectory = p.join(Platform.environment['ProgramData'] ?? r'C:\ProgramData', 'PlugAgente');
    if (!p.equals(context['dataDirectory'] as String, expectedDirectory)) return 3;
    if ((await checkInstallationBundle(bundle)).isError()) return 3;
    final secrets = WindowsUpdateSecretsSnapshot();
    if (context['restoring'] == true) {
      if ((await secrets.restoreEncrypted(context['secretsSnapshot'] as String)).isError()) return 3;
      return (await updater.confirmRestoration(args[1], args[2])).isSuccess() ? 0 : 3;
    }
    final settings = GlobalAppSettingsStore(filePath: p.join(expectedDirectory, 'settings.json'));
    await settings.initialize();
    database = AppDatabase(databaseFilePath: p.join(expectedDirectory, 'agent_config.db'));
    await database.getAllConfigs();
    final integrity = await database.customSelect('PRAGMA quick_check').get();
    if (integrity.length != 1 || integrity.single.data.values.single != 'ok') return 3;
    if ((await secrets.captureEncrypted()).isError()) return 3;
    await settings.flushPendingPersistence();
    if (settings.lastPersistError != null) return 3;
    await database.checkpointAndCloseForUpdate();
    database = null;
    return (await updater.confirmHealth(
          operationId: args[1],
          version: AppConstants.appVersion,
          nonce: args[2],
        )).isSuccess()
        ? 0
        : 3;
  } on Object {
    // Exceptions from credentials/migrations can contain secrets; report only exit status.
    return 3;
  } finally {
    if (database != null) {
      try {
        await database.close();
      } on Object {
        // The validation fails even if closing a failed migration also fails.
        exitCode = 3;
      }
    }
  }
}
