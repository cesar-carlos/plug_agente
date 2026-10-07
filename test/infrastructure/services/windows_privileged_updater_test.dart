import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_privileged_updater.dart';
import 'package:plug_agente/infrastructure/services/windows_privileged_updater.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  test('recovery required never proves native operation completion', () {
    const status = UpdaterStatus(phase: UpdaterPhase.recoveryRequired);
    expect(status.requiresRecovery, isTrue);
    expect(status.terminal, isFalse);
  });
  const operation = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const nonce = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  test('probation and restoration identify the actual requesting application process', () async {
    final commands = <String>[];
    final updater = WindowsPrivilegedUpdater(
      requestTransport: (request) async {
        expect(request['operationId'], operation);
        expect(request['nonce'], nonce);
        expect(request['appPid'], pid);
        commands.add(request['command']! as String);
        return const Success({'ok': true});
      },
    );
    expect((await updater.validationContext(operation, nonce)).isSuccess(), isTrue);
    expect((await updater.confirmHealth(operationId: operation, version: '1.8.7+1', nonce: nonce)).isSuccess(), isTrue);
    expect((await updater.confirmRestoration(operation, nonce)).isSuccess(), isTrue);
    expect(commands, ['validationContext', 'health', 'restored']);
  });
  test('revoked enrollment remains queryable and cannot apply', () async {
    final updater = WindowsPrivilegedUpdater(
      requestTransport: (request) async {
        expect(request, {'command': 'capabilities'});
        return const Success({
          'capabilities': {
            'protocol': 1,
            'authorized': false,
            'applicationReady': true,
            'channel': 'beta',
            'approved': ['app.files'],
          },
        });
      },
    );
    final capabilities = (await updater.capabilities()).getOrThrow();
    expect(capabilities.canApplyAutomatically, isFalse);
    expect(capabilities.channel, 'beta');
    expect(capabilities.approved, ['app.files']);
  });
  test('administrative enrollment alone does not mean application readiness', () async {
    final updater = WindowsPrivilegedUpdater(
      requestTransport: (_) async => const Success({
        'capabilities': {
          'protocol': 1,
          'authorized': true,
          'applicationReady': false,
          'channel': 'stable',
          'approved': ['app.files'],
        },
      }),
    );
    expect((await updater.capabilities()).getOrThrow().canApplyAutomatically, isFalse);
  });
  test('dispatch preserves nonce and is distinct from installation completion', () async {
    final updater = WindowsPrivilegedUpdater(
      requestTransport: (request) async {
        expect(request['operationId'], operation);
        expect(request['command'], 'start');
        return const Success({
          'status': {'protocol': 1, 'state': 'waitingForExit', 'operationId': operation},
          'healthNonce': nonce,
        });
      },
    );
    final confirmation = (await updater.start(
      operationId: operation,
      appPid: 123,
      dataDirectory: r'C:\ProgramData\PlugAgente',
      encryptedSecretsSnapshot: 'encrypted',
    )).getOrThrow();
    expect(confirmation.healthNonce, nonce);
    expect(confirmation.status.phase, UpdaterPhase.waitingForExit);
    expect(confirmation.status.terminal, isFalse);
  });
  test('dispatch rejects a mismatched operation or absent nonce', () async {
    for (final response in <Map<String, dynamic>>[
      {
        'status': {'protocol': 1, 'state': 'waitingForExit', 'operationId': nonce},
        'healthNonce': nonce,
      },
      {
        'status': {'protocol': 1, 'state': 'waitingForExit', 'operationId': operation},
      },
    ]) {
      final updater = WindowsPrivilegedUpdater(requestTransport: (_) async => Success(response));
      expect(
        (await updater.start(
          operationId: operation,
          appPid: 123,
          dataDirectory: 'data',
          encryptedSecretsSnapshot: 'encrypted',
        )).isError(),
        isTrue,
      );
    }
  });
  test('invalid protocol types and unknown states fail closed', () async {
    for (final response in <Map<String, dynamic>>[
      {
        'status': {'protocol': 1.0, 'state': 'idle'},
      },
      {
        'status': {'protocol': 1, 'state': 'newUnrecognizedPhase'},
      },
      {
        'status': {'protocol': 1, 'state': 'idle', 'operationId': '../outside'},
      },
      {
        'status': {'protocol': 1, 'state': 'preparing', 'ownedByCaller': 'true'},
      },
      {
        'status': {'protocol': 1, 'state': 'completed', 'finalizationPending': 0},
      },
      {
        'status': {'protocol': 1, 'state': 'deferred', 'retryAfterUnixMillis': 'tomorrow'},
      },
    ]) {
      final updater = WindowsPrivilegedUpdater(requestTransport: (_) async => Success(response));
      expect((await updater.status()).isError(), isTrue);
    }
  });
  test('old supervisor lacks the additive recovery capability and cannot apply', () async {
    final updater = WindowsPrivilegedUpdater(
      requestTransport: (_) async => const Success({
        'capabilities': {
          'protocol': 1,
          'authorized': true,
          'applicationReady': true,
          'channel': 'stable',
          'approved': <String>[],
        },
      }),
    );
    expect((await updater.capabilities()).getOrThrow().canApplyAutomatically, isFalse);
  });
  test('recovery IPC accepts only operation and application identity', () async {
    final updater = WindowsPrivilegedUpdater(
      requestTransport: (request) async {
        expect(request, {'command': 'recoverApplication', 'operationId': operation, 'appPid': 123});
        return const Success({
          'status': {
            'protocol': 1,
            'state': 'waitingForExit',
            'operationId': operation,
            'restartOnly': true,
            'ownedByCaller': true,
            'retryAfterUnixMillis': 1770000000000,
          },
        });
      },
    );
    final status = (await updater.requestApplicationRecovery(operationId: operation, appPid: 123)).getOrThrow();
    expect(status.restartOnly, isTrue);
    expect(status.retryAfter, DateTime.fromMillisecondsSinceEpoch(1770000000000, isUtc: true));
  });
  test('typed transport failure is preserved across capability query', () async {
    final failure = domain.ConfigurationFailure.withContext(
      message: 'Serviço indisponível.',
      context: {'reason': 'updater_unavailable'},
    );
    final updater = WindowsPrivilegedUpdater(requestTransport: (_) async => Failure(failure));
    expect((await updater.capabilities()).exceptionOrNull(), same(failure));
  });
}
