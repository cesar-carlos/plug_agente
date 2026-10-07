import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/application/services/update_maintenance_admission.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/stores/drift_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/hub_session_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_odbc_credential_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/odbc_credential_store.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  test('hub session, credentials and RPC caches cannot write after SQLite closes', () async {
    final admission = UpdateMaintenanceAdmission();
    addTearDown(admission.dispose);
    final database = AppDatabase(executor: NativeDatabase.memory());
    final session = HubSessionStore(database, authSecretStore: NoopHubAuthSecretStore(), maintenanceGate: admission);
    final credentials = OdbcCredentialStore(
      database,
      credentialSecretStore: NoopOdbcCredentialSecretStore(),
      maintenanceGate: admission,
    );
    final tokens = ClientTokenRepository(ClientTokenLocalDataSource(database), maintenanceGate: admission);
    final cache = DriftIdempotencyStore(database, maintenanceGate: admission);
    admission.transition('op', UpdateMaintenancePhase.draining);
    await database.close();
    admission.transition('op', UpdateMaintenancePhase.resourcesClosed);
    for (final result in [
      await session.readSession('cfg'),
      await session.writeSessionTokens('cfg', const AuthToken(token: 'access', refreshToken: 'refresh')),
      await credentials.readCredentials('cfg'),
      await tokens.listTokens(),
      await tokens.revokeToken('token'),
    ]) {
      expect(result.exceptionOrNull().toString(), contains('manutenção'));
    }
    await expectLater(
      cache.getRecord('request'),
      throwsA(predicate<Object>((e) => e.toString().contains('manutenção'))),
    );
    await expectLater(
      cache.purgeExpiredEntries(),
      throwsA(predicate<Object>((e) => e.toString().contains('manutenção'))),
    );
    await expectLater(tokens.replaceTokens([]), throwsA(predicate<Object>((e) => e.toString().contains('manutenção'))));
    expect(() => admission.transition('op', UpdateMaintenancePhase.operational), throwsStateError);
  });
  test('SQL and action admission allow only operation-bound internal exit work', () async {
    final admission = UpdateMaintenanceAdmission();
    final sql = SqlExecutionQueue(maxQueueSize: 4, maxConcurrentWorkers: 1, maintenanceGate: admission);
    final actions = ActionExecutionQueue(maintenanceGate: admission);
    sql.pauseAdmissionForMaintenance('op');
    actions.pauseAdmissionForMaintenance('op');
    admission.transition('op', UpdateMaintenancePhase.draining);
    Future<Result<String>> submitAction() => actions.enqueue(
      AgentActionQueueRequest<String>(
        actionId: 'exit',
        executionId: 'exit1',
        policies: const AgentActionDefinitionPolicies(),
        task: () async => const Success('exit'),
      ),
    );
    expect((await sql.submit(() async => const Success('normal'))).isError(), isTrue);
    expect((await submitAction()).isError(), isTrue);
    expect((await admission.internal('op', () => sql.submit(() async => const Success('exit')))).getOrThrow(), 'exit');
    expect((await admission.internal('op', submitAction)).getOrThrow(), 'exit');
    admission.transition('op', UpdateMaintenancePhase.resourcesClosed);
    expect(() => admission.internal('op', submitAction), throwsStateError);
    actions.dispose();
    sql.dispose();
  });

  test('real repository rejects reads and writes before touching a closed SQLite', () async {
    final admission = UpdateMaintenanceAdmission();
    final database = AppDatabase(executor: NativeDatabase.memory());
    final repository = AgentActionRepository(database, maintenanceGate: admission);
    expect((await repository.listDefinitions()).isSuccess(), isTrue);
    admission.transition('op', UpdateMaintenancePhase.draining);
    expect((await repository.listDefinitions()).isError(), isTrue);
    expect((await admission.internal('op', repository.listDefinitions)).isSuccess(), isTrue);
    await database.close();
    admission.transition('op', UpdateMaintenancePhase.resourcesClosed);
    final read = await repository.listDefinitions();
    final write = await repository.deleteDefinition('missing');
    expect(read.exceptionOrNull().toString(), contains('manutenção'));
    expect(write.exceptionOrNull().toString(), contains('manutenção'));
  });

  test('settings reject all mutations atomically during maintenance', () async {
    final dir = await Directory.systemTemp.createTemp('maintenance_settings_');
    final admission = UpdateMaintenanceAdmission();
    final settings = GlobalAppSettingsStore(filePath: '${dir.path}/settings.json')
      ..writeAdmission = admission.checkSettingsWrite;
    await settings.initialize();
    await settings.setBool('settings.enabled', true);
    admission.transition('op', UpdateMaintenancePhase.resourcesClosed);
    await expectLater(settings.setBool('settings.enabled', false), throwsException);
    await expectLater(settings.remove('settings.enabled'), throwsException);
    await expectLater(settings.setValues({'auto_update.test': 'evidence', 'settings.enabled': false}), throwsException);
    expect(settings.getBool('settings.enabled'), isTrue);
    expect(settings.getString('auto_update.test'), isNull);
    await settings.setString('auto_update.test', 'evidence');
    await settings.flushPendingPersistence();
    await dir.delete(recursive: true);
  });

  test('stop leaves in-flight purge visible until it actually finishes', () async {
    final pending = Completer<Result<int>>();
    final runner = PeriodicPurgeRunner(
      purge: () => pending.future,
      interval: const Duration(days: 1),
      logName: 'test',
      successLogMessage: (n) => '$n',
      failureLogMessage: 'failure',
    );
    runner.start();
    final purge = runner.purgeNow();
    runner.stop();
    expect(runner.isRunning, isFalse);
    expect(runner.isIdle, isFalse);
    pending.complete(const Success(0));
    await purge;
    expect(runner.isIdle, isTrue);
  });
}
