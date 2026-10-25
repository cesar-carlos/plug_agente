import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/installation_preparation_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_installation_preparation_monitor.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  const operation = '0123456789abcdef0123456789abcdef';
  test('concurrent and repeated requests execute preparation and exit once', () async {
    final pending = Completer<Result<void>>();
    var prepares = 0;
    var closes = 0;
    final service = InstallationPreparationService(
      prepareMaintenance: (_) {
        prepares++;
        return pending.future;
      },
      closeApplication: () async {
        closes++;
      },
      cancelMaintenance: () {},
    );
    final first = service.prepare(operation);
    final second = service.prepare(operation);
    expect(identical(first, second), isTrue);
    expect(service.state, InstallationPreparationState.waiting);
    expect(
      (await service.prepare('fedcba9876543210fedcba9876543210')).exceptionOrNull(),
      isA<domain.ValidationFailure>(),
    );
    pending.complete(const Success(unit));
    expect((await first).getOrThrow(), InstallationPreparationState.closing);
    await service.prepare(operation);
    await Future.wait([service.close(), service.close()]);
    expect(prepares, 1);
    expect(closes, 1);
  });

  for (final context in [
    <String, dynamic>{},
    {'outcome_unknown': true},
    {'resources_closed': true},
  ]) {
    test('maintenance failure preserves evidence and never closes: $context', () async {
      var closes = 0;
      final failure = domain.ConfigurationFailure.withContext(message: 'Maintenance blocked', context: context);
      final service = InstallationPreparationService(
        prepareMaintenance: (_) async => Failure(failure),
        closeApplication: () async {
          closes++;
        },
        cancelMaintenance: () {},
      );
      expect((await service.prepare(operation)).exceptionOrNull(), same(failure));
      expect(
        service.state,
        context.isEmpty ? InstallationPreparationState.blocked : InstallationPreparationState.recoveryRequired,
      );
      await service.close();
      expect(closes, 0);
    });
  }

  test('lost exit result is never replayed', () async {
    var closes = 0;
    final cause = StateError('exit result lost');
    final service = InstallationPreparationService(
      prepareMaintenance: (_) async => const Success(unit),
      closeApplication: () async {
        closes++;
        throw cause;
      },
      cancelMaintenance: () {},
    );
    await service.prepare(operation);
    final result = await service.close();
    expect(result.exceptionOrNull(), isA<domain.ConfigurationFailure>());
    expect(service.state, InstallationPreparationState.recoveryRequired);
    await service.prepare(operation);
    expect((await service.close()).exceptionOrNull(), same(result.exceptionOrNull()));
    expect(closes, 1);
  });

  test('cancellation reaches the maintenance owner without starting exit', () async {
    var cancelled = false;
    var closes = 0;
    final service = InstallationPreparationService(
      prepareMaintenance: (_) async => const Success(unit),
      closeApplication: () async {
        closes++;
      },
      cancelMaintenance: () {
        cancelled = true;
      },
    );
    service.cancel();
    expect((await service.prepare(operation)).isError(), isTrue);
    expect(service.state, InstallationPreparationState.cancelled);
    expect(cancelled, isTrue);
    expect(closes, 0);
  });
}
