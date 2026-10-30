import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_admission.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class _Tokens extends Mock implements IClientTokenRepository {}

class _Journal extends Mock implements IActionIoJournal {}

class _Sessions extends Mock implements IActionIoSessionLookup {}

void main() {
  var revoked = false;
  const client = 'client';
  ClientTokenSummary token() => ClientTokenSummary(
    id: 'token',
    clientId: client,
    agentId: 'agent',
    createdAt: DateTime.utc(2026),
    isRevoked: revoked,
    allTables: false,
    allViews: false,
    rules: const [],
    payload: const {
      'agent_action_scopes': ['agent_actions.*'],
    },
  );

  const intent = ActionIoSessionIntent(
    executionId: 'e',
    installationId: 'i',
    agentId: 'agent',
    clientId: 'client',
    actionId: 'action',
    idempotencyKey: 'key',
    fingerprint: 'f',
    triggerId: 't',
    definitionHash: 'd',
  );
  final io = ActionIoConfiguration(closeInput: true);
  setUp(() => revoked = false);

  test('request expiring during local validation never claims an execution', () async {
    final tokens = _Tokens();
    final journal = _Journal();
    final sessions = _Sessions();
    var active = true;
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(token()));
    when(
      () => sessions.previewClaim(intent, io: io),
    ).thenAnswer((_) async => const Success(ActionIoExecutionLookup(null)));
    when(
      () => journal.claim(intent, io: io),
    ).thenAnswer((_) async => const Success(ActionIoSessionClaim(executionId: 'e', created: true)));
    final admission = ActionIoAdmission(
      authorization: ActionIoAuthorization(tokens),
      journal: journal,
      sessions: sessions,
      accepting: () => true,
      validateLocalIntent: (_) async {
        active = false;
        return const Success(unit);
      },
    );
    final result = await admission.admit(
      intent: intent,
      io: io,
      credential: 'opaque',
      isRequestActive: () => active,
    );
    expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_REQUEST_EXPIRED');
    verifyZeroInteractions(journal);
  });

  for (final change in <String, ClientTokenSummary Function(ClientTokenSummary)>{
    'Client changed': (record) => record.copyWith(clientId: 'different-client'),
    'agent binding removed': (record) => record.copyWith(agentId: null),
    'I/O scope removed': (record) => record.copyWith(
      payload: const {
        'agent_action_scopes': ['agent_actions.run', 'agent_actions.validate_run'],
      },
    ),
    'action removed from allowlist': (record) => record.copyWith(
      payload: const {
        'agent_action_scopes': ['agent_actions.*'],
        'agent_actions': {
          'action_ids': ['another-action'],
        },
      },
    ),
  }.entries) {
    test('${change.key} while local approval is checked prevents a journal claim', () async {
      var current = token();
      final tokens = _Tokens();
      final journal = _Journal();
      final sessions = _Sessions();
      when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(current));
      when(
        () => sessions.previewClaim(intent, io: io),
      ).thenAnswer((_) async => const Success(ActionIoExecutionLookup(null)));
      var validations = 0;
      final admission = ActionIoAdmission(
        authorization: ActionIoAuthorization(tokens),
        journal: journal,
        sessions: sessions,
        accepting: () => true,
        validateLocalIntent: (_) async {
          validations++;
          current = change.value(current);
          return const Success(unit);
        },
      );
      final result = await admission.admit(intent: intent, io: io, credential: 'opaque');
      expect(validations, 1);
      expect(
        result.exceptionOrNull(),
        isA<ActionAuthorizationFailure>().having((failure) => failure.code, 'code', 'ACTION_IO_UNAUTHORIZED'),
      );
      verify(() => tokens.getTokenPolicySummaryByHash(any())).called(2);
      verifyZeroInteractions(journal);
    });
  }

  test('duplicate recovers original execution without validating edited definition or claiming', () async {
    revoked = false;
    final tokens = _Tokens();
    final journal = _Journal();
    final sessions = _Sessions();
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(token()));
    when(() => sessions.previewClaim(intent, io: io)).thenAnswer(
      (_) async => const Success(
        ActionIoExecutionLookup(
          ActionIoSessionReference(
            executionId: 'original',
            installationId: 'i',
            agentId: 'agent',
            clientId: 'client',
            actionId: 'action',
          ),
        ),
      ),
    );
    var validations = 0;
    final admission = ActionIoAdmission(
      authorization: ActionIoAuthorization(tokens),
      journal: journal,
      sessions: sessions,
      accepting: () => true,
      validateLocalIntent: (_) async {
        validations++;
        return Failure(ActionValidationFailure('Definition edited after original admission'));
      },
    );
    final result = (await admission.admit(intent: intent, io: io, credential: 'opaque')).getOrThrow();
    expect(result.executionId, 'original');
    expect(result.created, isFalse);
    expect(result.closeMessageId, ActionIoLimits.closeMessageId);
    expect(validations, 0);
    verifyZeroInteractions(journal);
  });
  test('validation never claims; admission returns only the journal result', () async {
    final tokens = _Tokens();
    final journal = _Journal();
    final sessions = _Sessions();
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(token()));
    when(
      () => sessions.previewClaim(intent, io: io),
    ).thenAnswer((_) async => const Success(ActionIoExecutionLookup(null)));
    when(
      () => journal.claim(intent, io: io),
    ).thenAnswer((_) async => const Success(ActionIoSessionClaim(executionId: 'e', created: true)));
    final admission = ActionIoAdmission(
      authorization: ActionIoAuthorization(tokens),
      journal: journal,
      sessions: sessions,
      accepting: () => true,
      validateLocalIntent: (_) async => const Success(unit),
    );
    expect((await admission.validate(intent: intent, io: io, credential: 'opaque')).getOrThrow().session, isNull);
    verifyNever(() => journal.claim(intent, io: io));
    expect((await admission.admit(intent: intent, io: io, credential: 'opaque')).getOrThrow().created, isTrue);
    verify(() => journal.claim(intent, io: io)).called(1);
  });
  test('revocation or maintenance during local validation prevents durable admission', () async {
    for (final revoke in [true, false]) {
      revoked = false;
      var accepting = true;
      final tokens = _Tokens();
      final journal = _Journal();
      final sessions = _Sessions();
      when(
        () => sessions.previewClaim(intent, io: io),
      ).thenAnswer((_) async => const Success(ActionIoExecutionLookup(null)));
      when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(token()));
      final admission = ActionIoAdmission(
        authorization: ActionIoAuthorization(tokens),
        journal: journal,
        sessions: sessions,
        accepting: () => accepting,
        validateLocalIntent: (_) async {
          if (revoke) {
            revoked = true;
          } else {
            accepting = false;
          }
          return const Success(unit);
        },
      );
      expect((await admission.admit(intent: intent, io: io, credential: 'opaque')).isError(), isTrue);
      verifyZeroInteractions(journal);
    }
  });
}
