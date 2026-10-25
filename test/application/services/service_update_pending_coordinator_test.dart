import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/services/pending_silent_update_reconciler.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/service_update_pending_coordinator.dart';
import 'package:plug_agente/application/services/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/repositories/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/infrastructure/repositories/update_preferences_repository.dart';
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
    offline = false;
    cancelLost = false;
    cancellations = 0;
    finished = 0;
    status = {'protocol': 1, 'state': 'preparing', 'operationId': operation, 'version': version, 'ownedByCaller': true};
    coordinator = ServiceUpdatePendingCoordinator(
      updater: WindowsPrivilegedUpdater(
        requestTransport: (request) async {
          if (offline) return Failure(domain.ConfigurationFailure('Serviço indisponível.'));
          if (request['command'] == 'cancel') {
            cancellations++;
            // Observe a fresh disk-backed reader before acknowledging IPC.
            final disk = GlobalAppSettingsStore(filePath: '${directory.path}/settings.json');
            await disk.initialize();
            final record = await SettingsBackedPendingSilentUpdateStore(
              preferences: UpdatePreferencesRepository(settingsStore: disk),
            ).read();
            expect((record! as PendingSilentUpdateService).cancelRequested, isTrue);
            status = {...status, 'state': 'deferred', 'reason': 'cancelled_before_installation'};
            if (cancelLost) return Failure(domain.ConfigurationFailure('Resposta perdida.'));
          }
          return Success({'status': status});
        },
      ),
      onFinished: (_) async => finished++,
      store: store,
      flush: settings.flushPendingPersistence,
      clock: () => now,
      stagedTtl: const Duration(days: 7),
    );
  });

  tearDown(() async {
    await settings.flushPendingPersistence();
    await directory.delete(recursive: true);
  });

  Future<void> stage({DateTime? time, DateTime? dispatch}) => store.write(
    PendingSilentUpdateService(
      version: version,
      startedAt: time ?? now,
      operationId: operation,
      dispatchAttemptedAt: dispatch,
    ),
  );

  test('boot reconciliation presents attention and unavailable status as recovery', () async {
    await stage();
    final reconciler = PendingSilentUpdateReconciler(
      pendingStore: store,
      servicePending: coordinator,
      launcherStatusReader: const NoopSilentUpdateLauncherStatusReader(),
      automaticFailureBreaker: PersistentCircuitBreaker(
        persistence: InMemoryCircuitBreakerPersistence(),
        threshold: 3,
        cooldown: const Duration(minutes: 5),
        logName: 'test',
      ),
      feedUrlResolver: () => null,
      checkIdRecorder: UpdateCheckIdRecorder(),
      clock: () => now,
    );
    UpdateCheckDiagnostics? diagnostics;
    for (final unavailable in [false, true]) {
      offline = unavailable;
      status = {...status, 'ownedByCaller': false};
      await reconciler.reconcile(
        PendingSilentUpdateReconcileRequest(
          onDiagnosticsUpdated: (value) => diagnostics = value,
          persistDiagnostics: () async {},
          pushDiagnostics: () {},
          onCheckIdAssigned: (_) {},
        ),
      );
      expect(diagnostics?.completionSource, UpdateCheckCompletionSource.automaticRecoveryRequired);
      expect(await store.read(), isNotNull);
    }
  });

  test('wrong pending value type is corruption rather than absence', () async {
    await settings.setInt(pendingSilentUpdateSettingsKey, 12);
    expect((await store.load()).exceptionOrNull(), isA<domain.ValidationFailure>());
  });

  for (final content in ['{invalid', '{"auto_update.pending_silent_update":{}}']) {
    test('corrupted settings stays blocked across restarts: $content', () async {
      final file = File('${directory.path}/broken.json');
      await file.writeAsString(content);
      for (var attempt = 0; attempt < 2; attempt++) {
        final disk = GlobalAppSettingsStore(filePath: file.path);
        await disk.initialize();
        final pending = SettingsBackedPendingSilentUpdateStore(
          preferences: UpdatePreferencesRepository(settingsStore: disk),
        );
        expect((await pending.load()).exceptionOrNull(), isA<domain.ValidationFailure>());
        expect(await file.readAsString(), content);
      }
    });
  }

  test('corrupted pending is a typed failure and cannot authorize cancellation', () async {
    await settings.setString(pendingSilentUpdateSettingsKey, '{broken');
    final result = await store.load();
    expect(result.exceptionOrNull(), isA<domain.ValidationFailure>());
    expect((await coordinator.reconcile(cancel: true)).isError(), isTrue);
    expect(cancellations, 0);
    expect(settings.getString(pendingSilentUpdateSettingsKey), '{broken');
  });

  test('missing pending is a successful empty snapshot', () async {
    expect((await store.load()).getOrThrow().pending, isNull);
  });

  test('cancellation waits for the complete dispatch transaction', () async {
    await stage();
    final entered = Completer<void>();
    final release = Completer<void>();
    final dispatch = coordinator.dispatch((resolution) async {
      expect(resolution.getOrThrow().decision, ServicePendingDecision.ready);
      entered.complete();
      await release.future;
      status = {...status, 'state': 'waitingForExit'};
      return const Success(unit);
    });
    await entered.future;
    final cancellation = coordinator.reconcile(cancel: true);
    await Future<void>.delayed(Duration.zero);
    expect(cancellations, 0);
    release.complete();
    expect((await dispatch).isSuccess(), isTrue);
    expect((await cancellation).getOrThrow().decision, ServicePendingDecision.active);
    expect(cancellations, 0);
  });

  test('failed durable save blocks cached readiness until a confirmed restore', () async {
    final parent = Directory('${directory.path}/private');
    await parent.create();
    final disk = GlobalAppSettingsStore(filePath: '${parent.path}/settings.json');
    await disk.initialize();
    final durable = SettingsBackedPendingSilentUpdateStore(
      preferences: UpdatePreferencesRepository(settingsStore: disk),
    );
    final ready = PendingSilentUpdateService(version: version, startedAt: now, operationId: operation);
    await durable.write(ready);
    await File('${parent.path}/settings.json').delete();
    await parent.delete();
    final blocker = File(parent.path);
    await blocker.writeAsString('private test obstruction');
    final result = await durable.save(ready.copyWith(dispatchAttemptedAt: now));
    expect(result.exceptionOrNull(), isA<domain.ConfigurationFailure>());
    expect((await durable.load()).isError(), isTrue);
    await blocker.delete();
    await parent.create();
    expect((await durable.save(ready)).isSuccess(), isTrue);
    final fresh = GlobalAppSettingsStore(filePath: '${parent.path}/settings.json');
    await fresh.initialize();
    final restored = await SettingsBackedPendingSilentUpdateStore(
      preferences: UpdatePreferencesRepository(settingsStore: fresh),
    ).read();
    expect((restored! as PendingSilentUpdateService).dispatchAttemptedAt, isNull);
  });

  test('service pending round trips without helper paths', () async {
    await stage();
    expect((await coordinator.reconcile()).getOrThrow().decision, ServicePendingDecision.ready);
    final pending = await store.read();
    expect(pending, isA<PendingSilentUpdateService>());
    expect(pending!.toJson().containsKey('launcherPath'), isFalse);
  });
  test('incomplete old service records never authorize application', () {
    expect(
      PendingSilentUpdate.fromJson({
        'strategy': 'windowsService',
        'version': version,
        'installerPath': 'setup.exe',
        'serviceOperationId': '../invalid',
      }),
      isA<PendingSilentUpdateProbed>(),
    );
  });
  test('old service record with a real operation is cancelled before new preparation', () async {
    await store.write(
      PendingSilentUpdate.fromJson({
        'strategy': 'windowsService',
        'version': version,
        'startedAt': now.toIso8601String(),
        'serviceOperationId': operation,
      })!,
    );
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
    await stage();
    cancelLost = true;
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
    await stage();
    offline = true;
    expect((await coordinator.reconcile(cancel: true)).isError(), isTrue);
    expect(await store.read(), isNotNull);
    offline = false;
    await Future.wait([coordinator.reconcile(), coordinator.reconcile()]);
    expect(cancellations, 1);
    expect(await store.read(), isNull);
  });
  test('terminal status with unfinished finalization retains pending', () async {
    await stage();
    status['state'] = 'completed';
    status['finalizationPending'] = true;
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
