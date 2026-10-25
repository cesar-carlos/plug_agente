import 'package:fake_async/fake_async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/application/services/silent_update_scheduler.dart';
import 'package:plug_agente/core/constants/app_constants.dart';

void main() {
  group('SilentUpdateScheduler', () {
    setUp(() {
      dotenv.clean();
      dotenv.loadFromString(
        envString:
            'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
            'AUTO_UPDATE_QUIET_HOURS_START=22:00\n'
            'AUTO_UPDATE_QUIET_HOURS_END=06:00',
      );
    });

    for (final restart in [false, true]) {
      test('cancels obsolete boot jitter when restart=$restart', () {
        fakeAsync((async) {
          var calls = 0;
          final scheduler = SilentUpdateScheduler(
            automaticFailureBreaker: PersistentCircuitBreaker(
              persistence: InMemoryCircuitBreakerPersistence(),
              threshold: 3,
              cooldown: const Duration(minutes: 5),
              logName: 'test',
            ),
            bootJitterProvider: () => const Duration(seconds: 10),
          );
          scheduler.scheduleAndStart(
            runImmediately: true,
            onCheck: () async {
              calls++;
            },
          );
          async.elapse(const Duration(seconds: 5));
          scheduler.stop();
          if (restart) {
            scheduler.scheduleAndStart(
              runImmediately: true,
              onCheck: () async {
                calls++;
              },
            );
          }
          async.elapse(const Duration(seconds: 5));
          expect(calls, 0);
          async.elapse(const Duration(seconds: 5));
          expect(calls, restart ? 1 : 0);
          scheduler.stop();
        });
      });
    }

    test('observes synchronous and asynchronous callback failures', () {
      fakeAsync((async) {
        final scheduler = SilentUpdateScheduler(
          automaticFailureBreaker: PersistentCircuitBreaker(
            persistence: InMemoryCircuitBreakerPersistence(),
            threshold: 3,
            cooldown: const Duration(minutes: 5),
            logName: 'test',
          ),
        );
        scheduler.scheduleAndStart(runImmediately: true, onCheck: () => throw StateError('sync'));
        async.flushMicrotasks();
        scheduler.scheduleAndStart(runImmediately: true, onCheck: () async => throw StateError('async'));
        async.flushMicrotasks();
        scheduler.stop();
      });
    });

    test('isWithinQuietHours returns true inside configured overnight window', () {
      final scheduler = SilentUpdateScheduler(
        automaticFailureBreaker: PersistentCircuitBreaker(
          persistence: InMemoryCircuitBreakerPersistence(),
          threshold: 3,
          cooldown: const Duration(minutes: 5),
          logName: 'silent_update_scheduler_test',
          clock: () => DateTime.utc(2026, 6, 10, 3),
        ),
        clock: () => DateTime(2026, 6, 10, 3, 30),
      );

      expect(scheduler.isWithinQuietHours(), isTrue);
    });

    test('isWithinQuietHours returns false outside configured window', () {
      final scheduler = SilentUpdateScheduler(
        automaticFailureBreaker: PersistentCircuitBreaker(
          persistence: InMemoryCircuitBreakerPersistence(),
          threshold: 3,
          cooldown: const Duration(minutes: 5),
          logName: 'silent_update_scheduler_test',
          clock: () => DateTime.utc(2026, 6, 10, 12),
        ),
        clock: () => DateTime(2026, 6, 10, 12),
      );

      expect(scheduler.isWithinQuietHours(), isFalse);
    });

    test('buildCooldownResult returns cooldown outcome when breaker is open', () async {
      final breaker = PersistentCircuitBreaker(
        persistence: InMemoryCircuitBreakerPersistence(),
        threshold: 1,
        cooldown: const Duration(minutes: 5),
        logName: 'silent_update_scheduler_test',
        clock: () => DateTime.utc(2026, 6, 10, 12),
      );
      final scheduler = SilentUpdateScheduler(
        automaticFailureBreaker: breaker,
        clock: () => DateTime.utc(2026, 6, 10, 12),
      );
      UpdateCheckDiagnostics? captured;

      await breaker.recordFailure();
      final result = await scheduler.buildCooldownResult(
        feedUrl: 'https://example.com/appcast.xml',
        checkId: 'check-1',
        onDiagnostics: (diagnostics) => captured = diagnostics,
        persistDiagnostics: () async {},
      );

      expect(result, isNotNull);
      result!.fold(
        (outcome) => expect(outcome, SilentUpdateOutcome.cooldownActive),
        (_) => fail('Expected success'),
      );
      expect(captured?.completionSource, UpdateCheckCompletionSource.automaticCooldown);
      expect(captured?.currentVersion, AppConstants.appVersion);
    });
  });
}
