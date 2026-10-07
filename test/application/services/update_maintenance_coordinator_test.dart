import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/update_maintenance_coordinator.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;
import 'package:result_dart/result_dart.dart';

void main() {
  test('exit effects precede secret capture and a capture failure restores admission', () async {
    final sequence = <String>[];
    final coordinator = UpdateMaintenanceCoordinator(
      freezeAdmission: () => sequence.add('freeze'),
      restoreAdmission: () => sequence.add('restore'),
      isSafelyIdle: () => true,
      applyExitPolicies: (_) async { sequence.add('exit'); return const Success(unit); },
      beforeClose: () async { sequence.add('secrets'); return Failure(ConfigurationFailure('Snapshot indisponível.')); },
      flushAndCloseLocalData: () async { sequence.add('close'); return const Success(unit); });
    expect((await coordinator.prepare('attempt1')).isError(), isTrue);
    expect(sequence, ['freeze', 'exit', 'secrets', 'restore']);
  });

  test('exit secrets persistence and resource closure execute in order', () async {
    final sequence = <String>[];
    final coordinator = UpdateMaintenanceCoordinator(
      freezeAdmission: () => sequence.add('freeze'), restoreAdmission: () => sequence.add('restore'),
      isSafelyIdle: () => true,
      applyExitPolicies: (_) async { sequence.add('exit'); return const Success(unit); },
      beforeClose: () async { sequence.add('secrets'); return const Success(unit); },
      flushAndCloseLocalData: () async { sequence.add('flush-close'); return const Success(unit); });
    expect((await coordinator.prepare('attempt1')).getOrThrow(), MaintenanceDecision.ready);
    expect(sequence, ['freeze', 'exit', 'secrets', 'flush-close']);
  });

  test('unknown or thrown exit-policy outcome keeps admission blocked', () async {
    for (final throws in [false, true]) {
      var restored = false;
      final coordinator = UpdateMaintenanceCoordinator(
        freezeAdmission: () {},
        restoreAdmission: () => restored = true,
        isSafelyIdle: () => true,
        applyExitPolicies: (_) async {
          if (throws) throw StateError('unconfirmed execution');
          return Failure(
            ConfigurationFailure.withContext(
              message: 'Resultado incerto',
              context: const {'outcome_unknown': true},
            ),
          );
        },
        flushAndCloseLocalData: () async => const Success(unit),
      );
      expect((await coordinator.prepare('attempt1')).isError(), isTrue);
      coordinator.cancel();
      expect(restored, isFalse);
    }
  });
  test('cancellation does not resume admission while an exit policy is pending', () async {
    final policy = Completer<Result<void>>();
    var restored = false;
    var cleanup = false;
    final coordinator = UpdateMaintenanceCoordinator(
      freezeAdmission: () {},
      restoreAdmission: () => restored = true,
      isSafelyIdle: () => true,
      applyExitPolicies: (_) => policy.future,
      flushAndCloseLocalData: () async {
        cleanup = true;
        return const Success(unit);
      },
    );
    final first = coordinator.prepare('attempt1');
    coordinator.cancel();
    expect(restored, isFalse);
    expect((await coordinator.prepare('attempt2')).isError(), isTrue);
    policy.complete(const Success(unit));
    expect((await first).getOrThrow(), MaintenanceDecision.deferred);
    expect(restored, isTrue);
    expect(cleanup, isFalse);
  });
  test('busy operation defers after 60 seconds and restores admission', () async {
    var now = DateTime(2026);
    var frozen = false;
    var policies = 0;
    final coordinator = UpdateMaintenanceCoordinator(
      freezeAdmission: () => frozen = true,
      restoreAdmission: () => frozen = false,
      isSafelyIdle: () => false,
      applyExitPolicies: (_) async {
        policies++;
        return const Success(unit);
      },
      flushAndCloseLocalData: () async => const Success(unit),
      clock: () => now,
      wait: (duration) async => now = now.add(duration),
    );
    expect((await coordinator.prepare('attempt1')).getOrThrow(), MaintenanceDecision.deferred);
    expect(frozen, isFalse);
    expect(policies, 0);
    expect(coordinator.retryAfter, now.add(const Duration(minutes: 15)));
    expect((await coordinator.prepare('attempt2')).getOrThrow(), MaintenanceDecision.deferred);
  });

  test('exit policies run once per attempt across reversible retries', () async {
    var idle = true;
    var now = DateTime(2026);
    var policies = 0;
    final coordinator = UpdateMaintenanceCoordinator(
      freezeAdmission: () {},
      restoreAdmission: () {},
      isSafelyIdle: () => idle,
      applyExitPolicies: (_) async {
        policies++;
        idle = false;
        return const Success(unit);
      },
      flushAndCloseLocalData: () async => const Success(unit),
      clock: () => now,
    );
    expect((await coordinator.prepare('attempt1')).getOrThrow(), MaintenanceDecision.deferred);
    idle = true;
    now = now.add(const Duration(minutes: 15));
    expect((await coordinator.prepare('attempt1')).getOrThrow(), MaintenanceDecision.ready);
    expect(policies, 1);
  });

  test('unconfirmed local cleanup keeps admission blocked', () async {
    var restored = false;
    final coordinator = UpdateMaintenanceCoordinator(
      freezeAdmission: () {},
      restoreAdmission: () => restored = true,
      isSafelyIdle: () => true,
      applyExitPolicies: (_) async => const Success(unit),
      flushAndCloseLocalData: () async => Failure(ConfigurationFailure('checkpoint failed')),
    );
    expect((await coordinator.prepare('attempt1')).isError(), isTrue);
    coordinator.cancel();
    expect(restored, isFalse);
  });
}
