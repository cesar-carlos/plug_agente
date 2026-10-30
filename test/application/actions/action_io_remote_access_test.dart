import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_remote_access.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_concurrency_slots.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _Tokens extends Mock implements IClientTokenRepository {}

class _Input extends Mock implements IActionIoJournal {}

class _Output extends Mock implements IActionIoOutputJournal {}

class _Sessions extends Mock implements IActionIoSessionLookup {}

void main() {
  late _Tokens tokens;
  late _Input input;
  late _Output output;
  late _Sessions sessions;
  late ActionIoRemoteAccess access;
  late MetricsCollector metrics;
  var revoked = false;
  var client = 'client';
  var reads = 0;
  var scopes = <String>['agent_actions.*'];
  var cancelRequests = 0;
  ClientTokenSummary token({String? owner}) => ClientTokenSummary(
    id: 'token',
    clientId: owner ?? client,
    agentId: 'agent',
    createdAt: DateTime.utc(2026),
    isRevoked: revoked,
    allTables: false,
    allViews: false,
    rules: const [],
    payload: {'agent_action_scopes': scopes},
  );
  ActionIoSessionReference reference(String id, {String owner = 'client'}) => ActionIoSessionReference(
    executionId: id,
    installationId: 'installation',
    agentId: 'agent',
    clientId: owner,
    actionId: 'action',
  );
  setUp(() {
    tokens = _Tokens();
    input = _Input();
    output = _Output();
    sessions = _Sessions();
    metrics = MetricsCollector();
    revoked = false;
    client = 'client';
    reads = 0;
    scopes = ['agent_actions.*'];
    cancelRequests = 0;
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(token()));
    when(
      () => sessions.getSessionReference(any()),
    ).thenAnswer((call) async => Success(reference(call.positionalArguments[0] as String)));
    when(
      () => output.read(
        executionId: any(named: 'executionId'),
        clientId: any(named: 'clientId'),
        afterSequence: any(named: 'afterSequence'),
        maxBytes: any(named: 'maxBytes'),
      ),
    ).thenAnswer((_) async {
      reads++;
      return Success(ActionIoReadPage(events: [], nextSequence: 0, terminal: false, outputComplete: false));
    });
    access = ActionIoRemoteAccess(
      metrics: metrics.actionIoMetrics,
      installationId: 'installation',
      authorization: ActionIoAuthorization(tokens),
      input: input,
      output: output,
      sessions: sessions,
      requestCancel: (_) {
        cancelRequests++;
        return const Success(true);
      },
    );
  });
  Future<Result<ActionIoReadPage>> read({
    String execution = 'e',
    Duration wait = Duration.zero,
    DateTime? deadline,
    bool Function()? cancelled,
    void Function()? onWait,
    String connection = 'connection',
    String credential = 'credential',
  }) => access.read(
    executionId: execution,
    agentId: 'agent',
    credential: credential,
    connectionId: connection,
    afterSequence: 0,
    maxBytes: 65536,
    wait: wait,
    deadline: deadline ?? DateTime.now().add(const Duration(seconds: 30)),
    isCancelled: cancelled,
    onReadWait: onWait,
  );

  test('abandoned wait permits immediate replacement before its poll timer wakes', () async {
    var cancelled = false;
    final waiting = Completer<void>();
    final previous = read(wait: const Duration(seconds: 20), cancelled: () => cancelled, onWait: waiting.complete);
    await waiting.future;
    expect(metrics.getSnapshot()['action_io_readers_active'], 1);
    cancelled = true;
    final replacement = await read();
    final abandoned = await previous;
    expect(replacement.isSuccess(), isTrue);
    expect((abandoned.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READ_CANCELLED');
    expect((await read()).isSuccess(), isTrue);
    expect(cancelRequests, 0);
    expect(metrics.getSnapshot()['action_io_readers_active'], 0);
    expect(metrics.getSnapshot()['action_io_readers_peak'], 1);
    expect(metrics.getSnapshot()['action_io_remote_cancelled_total'], 1);
    expect(metrics.getSnapshot()['action_io_remote_success_total'], 2);
  });

  test('read metrics count redelivery bytes but never export payload or caller identities', () async {
    when(
      () => output.read(
        executionId: any(named: 'executionId'),
        clientId: any(named: 'clientId'),
        afterSequence: any(named: 'afterSequence'),
        maxBytes: any(named: 'maxBytes'),
      ),
    ).thenAnswer(
      (_) async => Success(
        ActionIoReadPage(
          events: [
            ActionIoOutputEvent(sequence: 0, stream: ActionIoStream.stdout, offset: 0, bytes: [0, 255, 26]),
          ],
          nextSequence: 1,
          terminal: true,
          outputComplete: true,
        ),
      ),
    );
    (await read()).getOrThrow();
    (await read()).getOrThrow();
    client = 'different-private-owner';
    expect((await read()).isError(), isTrue);
    final values = Map<String, Object>.fromEntries(
      metrics.getSnapshot().entries.where((entry) => entry.key.startsWith('action_io_')),
    );
    expect(values, {
      'action_io_readers_active': 0,
      'action_io_readers_peak': 1,
      'action_io_read_bytes_total': 6,
      'action_io_remote_calls_total': 3,
      'action_io_remote_success_total': 2,
      'action_io_remote_unauthorized_total': 1,
    });
  });

  test('authorized waiting reader frees a dispatch slot without double release', () async {
    final slots = RpcInboundConcurrencySlots();
    for (var i = 0; i < ConnectionConstants.maxConcurrentRpcHandlers; i++) {
      expect(slots.tryAcquireSlot(), isTrue);
    }
    expect(slots.tryAcquireSlot(), isFalse);
    var cancelled = false;
    final waiting = Completer<void>();
    final result = slots.runWithDeferredSlotRelease(
      () => read(
        wait: const Duration(seconds: 1),
        cancelled: () => cancelled,
        onWait: () {
          slots.releaseDeferredIfPresent();
          waiting.complete();
        },
      ),
    );
    await waiting.future;
    expect(slots.tryAcquireSlot(), isTrue);
    expect(slots.tryAcquireSlot(), isFalse);
    cancelled = true;
    expect((await result).isError(), isTrue);
    expect(slots.tryAcquireSlot(), isFalse);
    for (var i = 0; i < ConnectionConstants.maxConcurrentRpcHandlers; i++) {
      slots.releaseSlot();
    }
    expect((await read()).isSuccess(), isTrue);
  });

  test('late cleanup of an abandoned read cannot release its waiting replacement', () async {
    var oldCancelled = false;
    var newCancelled = false;
    final oldEntered = Completer<void>();
    final newEntered = Completer<void>();
    final old = read(wait: const Duration(seconds: 20), cancelled: () => oldCancelled, onWait: oldEntered.complete);
    await oldEntered.future;
    oldCancelled = true;
    final replacement = read(
      wait: const Duration(seconds: 20),
      cancelled: () => newCancelled,
      onWait: newEntered.complete,
    );
    try {
      await newEntered.future.timeout(const Duration(seconds: 5));
      expect((await old).isError(), isTrue);
      expect(((await read()).exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READER_LIMIT');
    } finally {
      newCancelled = true;
      await replacement;
    }
    expect((await read()).isSuccess(), isTrue);
  });

  test('unauthorized and immediate reads never transfer their dispatch slot', () async {
    var transfers = 0;
    expect((await read(onWait: () => transfers++)).isSuccess(), isTrue);
    revoked = true;
    expect((await read(wait: const Duration(seconds: 1), onWait: () => transfers++)).isError(), isTrue);
    expect(transfers, 0);
  });

  test('cancellation requires cancel scope and reauthorizes before requesting native stop', () async {
    when(() => output.cancelQueued('e', 'client')).thenAnswer((_) async => const Success(false));
    when(() => sessions.getExecutionSnapshot('e')).thenAnswer(
      (_) async => Success(
        ActionIoExecutionSnapshot(
          session: reference('e'),
          idempotencyKey: 'key',
          createdAt: DateTime.utc(2026),
          processState: 'running',
          stdinState: 'open',
          captureState: 'capturing',
          outputExpired: false,
        ),
      ),
    );
    Future<Result<ActionIoExecutionSnapshot>> cancel() =>
        access.cancel(executionId: 'e', agentId: 'agent', credential: 'credential');
    scopes = ['agent_actions.io', 'agent_actions.read_execution'];
    expect((await cancel()).isError(), isTrue);
    verifyNever(() => output.cancelQueued(any(), any()));
    scopes = ['agent_actions.io', 'agent_actions.cancel'];
    expect((await cancel()).getOrThrow().processState, 'running');
    expect(cancelRequests, 1);
    when(() => output.cancelQueued('e', 'client')).thenAnswer((_) async {
      revoked = true;
      return const Success(false);
    });
    expect((await cancel()).exceptionOrNull(), isA<ActionAuthorizationFailure>());
    expect(cancelRequests, 1);
  });

  test('execution metadata checks ownership and revocation after journal read', () async {
    var snapshotReads = 0;
    var revokeDuringRead = false;
    when(() => sessions.getExecutionSnapshot('e')).thenAnswer((_) async {
      snapshotReads++;
      revoked = revokeDuringRead;
      return Success(
        ActionIoExecutionSnapshot(
          session: reference('e'),
          idempotencyKey: 'key',
          createdAt: DateTime.utc(2026),
          processState: 'unknown',
          stdinState: 'failed',
          captureState: 'incomplete',
          outputExpired: false,
        ),
      );
    });
    Future<Result<ActionIoExecutionSnapshot>> fetch() =>
        access.execution(executionId: 'e', agentId: 'agent', credential: 'credential');
    client = 'other';
    expect((await fetch()).exceptionOrNull(), isA<ActionAuthorizationFailure>());
    expect(snapshotReads, 0);
    client = 'client';
    expect((await fetch()).getOrThrow().processState, 'unknown');
    revokeDuringRead = true;
    expect((await fetch()).exceptionOrNull(), isA<ActionAuthorizationFailure>());
    expect(snapshotReads, 2);
  });

  test('cross-client read is refused before output lookup', () async {
    client = 'other';
    expect((await read()).isError(), isTrue);
    expect(reads, 0);
  });

  test('long poll reauthorizes and discards the page when the credential was revoked', () async {
    when(
      () => output.read(
        executionId: any(named: 'executionId'),
        clientId: any(named: 'clientId'),
        afterSequence: any(named: 'afterSequence'),
        maxBytes: any(named: 'maxBytes'),
      ),
    ).thenAnswer((_) async {
      revoked = true;
      return Success(ActionIoReadPage(events: [], nextSequence: 0, terminal: false, outputComplete: false));
    });
    final result = await read(wait: const Duration(milliseconds: 50));
    expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
    verify(() => tokens.getTokenPolicySummaryByHash(any())).called(2);
  });

  test('deadline response reserve prevents a long poll from consuming the final five seconds', () async {
    expect(
      (await read(
        wait: const Duration(seconds: 20),
        deadline: DateTime.now().add(const Duration(seconds: 4)),
      )).isSuccess(),
      isTrue,
    );
    expect(reads, 1);
  });

  for (final restriction in ['allowlist', 'io-scope', 'read-scope']) {
    test('$restriction removed during long poll discards ready bytes and releases its reader', () async {
      var changed = false;
      when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async {
        final allowedScopes = !changed || restriction == 'allowlist'
            ? ['agent_actions.io', 'agent_actions.read_execution']
            : restriction == 'io-scope'
            ? ['agent_actions.read_execution']
            : ['agent_actions.io'];
        return Success(
          token().copyWith(
            payload: {
              'agent_actions': {
                'scopes': allowedScopes,
                'action_ids': changed && restriction == 'allowlist' ? ['other'] : ['action'],
              },
            },
          ),
        );
      });
      when(
        () => output.read(
          executionId: any(named: 'executionId'),
          clientId: any(named: 'clientId'),
          afterSequence: any(named: 'afterSequence'),
          maxBytes: any(named: 'maxBytes'),
        ),
      ).thenAnswer(
        (_) async => Success(
          ActionIoReadPage(
            events: changed
                ? [
                    ActionIoOutputEvent(sequence: 1, stream: .stdout, offset: 0, bytes: [0, 255, 26]),
                  ]
                : [],
            nextSequence: changed ? 1 : 0,
            terminal: false,
            outputComplete: false,
          ),
        ),
      );
      final waiting = Completer<void>();
      final pending = read(wait: const Duration(seconds: 20), onWait: waiting.complete);
      await waiting.future.timeout(const Duration(seconds: 2));
      changed = true;
      final denied = await pending.timeout(const Duration(seconds: 2));
      expect(denied.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(metrics.getSnapshot()['action_io_readers_active'], 0);
      expect(cancelRequests, 0);
      changed = false;
      expect((await read()).isSuccess(), isTrue);
    });
  }

  for (final expireOnAuthorization in [1, 2]) {
    test('deadline expiry during authorization $expireOnAuthorization refuses delivery and releases reader', () async {
      final start = DateTime.utc(2026, 10, 30);
      final deadline = start.add(const Duration(seconds: 30));
      var now = start;
      var authorizations = 0;
      when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async {
        authorizations++;
        if (authorizations == expireOnAuthorization) now = deadline;
        return Success(token());
      });
      access = ActionIoRemoteAccess(
        installationId: 'installation',
        authorization: ActionIoAuthorization(tokens),
        input: input,
        output: output,
        sessions: sessions,
        now: () => now,
      );

      final result = await read(deadline: deadline);
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_TIMEOUT');
      expect(reads, expireOnAuthorization - 1);

      // The timed-out request must not prevent the same owner reading again.
      now = start;
      expect((await read(deadline: deadline)).isSuccess(), isTrue);
    });
  }

  test('per-execution and per-client limits release leases after cancellation', () async {
    var cancelled = false;
    final waiting = [
      for (var i = 0; i < 8; i++) read(execution: 'e$i', wait: const Duration(seconds: 1), cancelled: () => cancelled),
    ];
    // Let all eight initial authorization/journal futures reach the wait.
    for (var i = 0; i < 20 && reads < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(reads, 8);
    expect(((await read(execution: 'e0')).exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READER_LIMIT');
    expect(((await read(execution: 'e8')).exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READER_LIMIT');
    // Rotation and another socket preserve the same authenticated Client quota.
    for (final execution in ['e0', 'e8']) {
      final otherConnection = await read(
        execution: execution,
        connection: 'reconnected',
        credential: 'rotated-credential',
      );
      expect((otherConnection.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READER_LIMIT');
    }
    cancelled = true;
    final cancelledResults = await Future.wait(waiting);
    expect(
      cancelledResults.every((r) => (r.exceptionOrNull()! as ActionFailure).code == 'ACTION_IO_READ_CANCELLED'),
      isTrue,
    );
    expect((await read(execution: 'e0')).isSuccess(), isTrue);
  });

  for (final limit in [16, 32]) {
    test('$limit-reader saturation preserves control access and replacement ownership', () async {
      final identities = {
        for (var i = 0; i < 5; i++) hashClientCredentialToken('credential-$i'): 'client-$i',
      };
      when(
        () => tokens.getTokenPolicySummaryByHash(any()),
      ).thenAnswer(
        (call) async => Success(
          token(
            owner: identities[call.positionalArguments[0]] ?? (throw StateError('Unregistered fixture credential')),
          ),
        ),
      );
      when(() => sessions.getSessionReference(any())).thenAnswer((call) async {
        final id = call.positionalArguments[0] as String;
        return Success(reference(id, owner: 'client-${int.parse(id) ~/ 8}'));
      });
      when(() => output.cancelQueued('0', 'client-0')).thenAnswer((_) async => const Success(false));
      when(() => sessions.getExecutionSnapshot('0')).thenAnswer(
        (_) async => Success(
          ActionIoExecutionSnapshot(
            session: reference('0', owner: 'client-0'),
            idempotencyKey: 'key',
            createdAt: DateTime.utc(2026),
            processState: 'running',
            stdinState: 'open',
            captureState: 'capturing',
            outputExpired: false,
          ),
        ),
      );
      final cancellations = List.filled(limit + 1, false);
      final entered = List.generate(limit + 1, (_) => Completer<void>());
      final pending = <Future<Result<ActionIoReadPage>>>[];
      when(
        () => input.admitInput(
          executionId: '0',
          clientId: 'client-0',
          messageId: 'input',
          sequence: 0,
          bytes: [0, 255],
        ),
      ).thenAnswer(
        (_) async => const Success(
          ActionIoMessageReceipt(
            executionId: '0',
            messageId: 'input',
            sequence: 0,
            state: .accepted,
            confirmedBytes: 0,
            nextInputSequence: 1,
            stdinState: .open,
          ),
        ),
      );
      Future<Result<ActionIoReadPage>> start(int id, {bool waiting = false, String? connection}) => access.read(
        executionId: '$id',
        agentId: 'agent',
        credential: 'credential-${id ~/ 8}',
        connectionId: connection ?? (limit == 16 ? 'shared' : 'connection-${id ~/ 16}'),
        afterSequence: 0,
        maxBytes: 65536,
        wait: waiting ? const Duration(seconds: 20) : Duration.zero,
        deadline: DateTime.now().add(const Duration(seconds: 30)),
        isCancelled: waiting ? () => cancellations[id] : null,
        onReadWait: waiting ? entered[id].complete : null,
      );
      try {
        for (var id = 0; id < limit; id++) {
          pending.add(start(id, waiting: true));
        }
        await Future.wait(entered.take(limit).map((entry) => entry.future)).timeout(const Duration(seconds: 5));
        final refusal = await start(limit);
        expect((refusal.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READER_LIMIT');
        if (limit == 16) expect((await start(limit, connection: 'other')).isSuccess(), isTrue);
        final sent = await access.send(
          executionId: '0',
          agentId: 'agent',
          credential: 'credential-0',
          messageId: 'input',
          sequence: 0,
          bytes: [0, 255],
        );
        expect(sent.getOrThrow().messageId, 'input');
        expect(
          (await access.cancel(executionId: '0', agentId: 'agent', credential: 'credential-0')).isSuccess(),
          isTrue,
        );
        expect(cancelRequests, 1);
        cancellations[0] = true;
        final replacement = start(limit, waiting: true);
        pending.add(replacement);
        await entered[limit].future.timeout(const Duration(seconds: 5));
        // The old reservation's finally must not decrement another reader's counters.
        await pending.first;
        expect((await start(1)).isError(), isTrue);
        final stillFull = await start(limit + 1);
        expect((stillFull.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_READER_LIMIT');
      } finally {
        cancellations.fillRange(0, cancellations.length, true);
        await Future.wait(pending);
      }
      expect((await start(0)).isSuccess(), isTrue);
    });
  }

  test('find uses stable installation agent client action scope rather than credential identity', () async {
    when(
      () => sessions.findExecution(
        installationId: 'installation',
        agentId: 'agent',
        clientId: 'client',
        actionId: 'action',
        idempotencyKey: 'key',
      ),
    ).thenAnswer((_) async => Success(ActionIoExecutionLookup(reference('e'))));
    final found = await access.find(
      agentId: 'agent',
      credential: 'rotated-credential',
      actionId: 'action',
      idempotencyKey: 'key',
    );
    expect(found.getOrThrow().session!.executionId, 'e');
  });
}
