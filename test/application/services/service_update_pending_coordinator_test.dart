import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/service_update_pending_coordinator.dart';
import 'package:plug_agente/application/services/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/services/windows_privileged_updater.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  const operation = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const version = '1.9.0+1';
  final now = DateTime(2026);
  late Directory directory;
  late GlobalAppSettingsStore settings;
  late SettingsBackedPendingSilentUpdateStore store;
  late ServiceUpdatePendingCoordinator coordinator;
  late Map<String, dynamic> status;
  var offline = false;
  var cancelLost = false;
  var cancellations = 0;
  var finished = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('service_pending_');
    settings = GlobalAppSettingsStore(filePath: '${directory.path}/settings.json');
    await settings.initialize();
    store = SettingsBackedPendingSilentUpdateStore(preferences: UpdatePreferencesRepository(settingsStore: settings));
    offline = false; cancelLost = false; cancellations = 0; finished = 0;
    status = {'protocol': 1, 'state': 'preparing', 'operationId': operation, 'version': version, 'ownedByCaller': true};
    coordinator = ServiceUpdatePendingCoordinator(
      updater: WindowsPrivilegedUpdater(requestTransport: (request) async {
        if (offline) return Failure(domain.ConfigurationFailure('Serviço indisponível.'));
        if (request['command'] == 'cancel') {
          cancellations++;
          // Observe a fresh disk-backed reader before acknowledging IPC.
          final disk = GlobalAppSettingsStore(filePath: '${directory.path}/settings.json');
          await disk.initialize();
          final record = await SettingsBackedPendingSilentUpdateStore(
            preferences: UpdatePreferencesRepository(settingsStore: disk)).read();
          expect((record! as PendingSilentUpdateService).cancelRequested, isTrue);
          status = {...status, 'state': 'deferred', 'reason': 'cancelled_before_installation'};
          if (cancelLost) return Failure(domain.ConfigurationFailure('Resposta perdida.'));
        }
        return Success({'status': status});
      }),
      onFinished: (_) async => finished++,
      store: store, flush: settings.flushPendingPersistence,
      clock: () => now, stagedTtl: const Duration(days: 7),
    );
  });

  tearDown(() async { await settings.flushPendingPersistence(); await directory.delete(recursive: true); });

  Future<void> stage({DateTime? time, DateTime? dispatch}) => store.write(PendingSilentUpdateService(
    version: version, startedAt: time ?? now, operationId: operation, dispatchAttemptedAt: dispatch));

  test('service pending round trips without helper paths', () async {
    await stage();
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.ready);
    final pending = await store.read();
    expect(pending, isA<PendingSilentUpdateService>());
    expect(pending!.toJson().containsKey('launcherPath'), isFalse);
  });
  test('incomplete old service records never authorize application', () {
    expect(PendingSilentUpdate.fromJson({'strategy': 'windowsService', 'version': version,
      'installerPath': 'setup.exe', 'serviceOperationId': '../invalid'}), isA<PendingSilentUpdateProbed>());
  });
  test('old service record with a real operation is cancelled before new preparation', () async {
    await store.write(PendingSilentUpdate.fromJson({'strategy': 'windowsService', 'version': version,
      'startedAt': now.toIso8601String(), 'serviceOperationId': operation})!);
    final record = (await store.read())! as PendingSilentUpdateService;
    expect(record.requiresNewPreparation, isTrue);
    expect(await coordinator.isReady(record), isFalse);
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.finished);
    expect(cancellations, 1);
  });
  test('cancel intent is durable before IPC and repeat cancellation is idempotent', () async {
    await stage();
    expect((await coordinator.reconcile(cancel: true)).getOrThrow().decision, ServicePendingDecision.finished);
    expect(await store.read(), isNull);
    expect((await coordinator.reconcile(cancel: true)).isSuccess(), isTrue);
    expect(cancellations, 1);
  });
  test('lost cancellation reply preserves intent and later reconciles completion', () async {
    await stage(); cancelLost = true;
    expect((await coordinator.reconcile(cancel: true)).isError(), isTrue);
    expect((await store.read() as PendingSilentUpdateService?)?.cancelRequested, isTrue);
    cancelLost = false;
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.finished);
    expect(cancellations, 1);
    expect(await store.read(), isNull);
  });
  test('expiration cancels prepared operation but preserves active operation', () async {
    await stage(time: now.subtract(const Duration(days: 8)));
    status['state'] = 'installing';
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.active);
    expect(await store.read(), isNotNull);
    expect(cancellations, 0);
    status['state'] = 'preparing';
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.finished);
    expect(cancellations, 1);
  });
  test('owned orphan is cancelled and other users remain protected', () async {
    status['ownedByCaller'] = false;
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.none);
    expect(cancellations, 0);
    expect(await store.read(), isNull);
    status['ownedByCaller'] = true;
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.finished);
    expect(cancellations, 1);
  });
  test('offline cancellation retains operation and serialized retries reconcile once', () async {
    await stage(); offline = true;
    expect((await coordinator.reconcile(cancel: true)).isError(), isTrue);
    expect(await store.read(), isNotNull);
    offline = false;
    await Future.wait([coordinator.reconcile(), coordinator.reconcile()]);
    expect(cancellations, 1);
    expect(await store.read(), isNull);
  });
  test('terminal status with unfinished finalization retains pending', () async {
    await stage(); status['state'] = 'completed'; status['finalizationPending'] = true;
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.active);
    expect(await store.read(), isNotNull);
    status['finalizationPending'] = false;
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.finished);
  });
  test('readiness query cannot consume completion or replay terminal accounting', () async {
    await stage();
    status['state'] = 'completed';
    final pending = (await store.read())! as PendingSilentUpdateService;
    expect(await coordinator.isReady(pending), isFalse);
    expect(await store.read(), isNotNull);
    expect(finished, 0);
    await Future.wait([coordinator.reconcile(), coordinator.reconcile()]);
    expect(finished, 1);
  });

  test('dispatch intent cannot become authority to dispatch again', () async {
    await stage(dispatch: now);
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.attention);
  });
}
