import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class _Repository extends Mock implements IClientTokenRepository {}

void main() {
  late _Repository repository;
  late ActionIoAuthorization authorization;
  final now = DateTime.utc(2026, 10, 28);
  ClientTokenSummary record({
    bool revoked = false,
    String client = 'client',
    String? agent = 'agent',
    Map<String, dynamic> payload = const {
      'agent_action_scopes': ['agent_actions.io', 'agent_actions.run'],
    },
  }) => ClientTokenSummary(
    id: 'token',
    clientId: client,
    agentId: agent,
    createdAt: now,
    isRevoked: revoked,
    allTables: false,
    allViews: false,
    rules: const [],
    payload: payload,
  );
  Future<Result<ActionIoPrincipal>> call({String credential = 'secret', String? owner}) => authorization.authorize(
    credential: credential,
    agentId: 'agent',
    actionId: 'action',
    operation: ActionIoOperation.sendInput,
    ownerClientId: owner,
  );
  setUp(() {
    repository = _Repository();
    authorization = ActionIoAuthorization(repository, now: () => now);
    when(() => repository.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(record()));
  });
  test('loads current metadata by credential hash and never loads the secret', () async {
    expect((await call(credential: ' Bearer secret ')).getOrThrow().clientId, 'client');
    verify(() => repository.getTokenPolicySummaryByHash(hashClientCredentialToken('secret'))).called(1);
    verifyNever(() => repository.getTokenSecret(any()));
  });
  test('a revocation between calls is effective without a cache TTL', () async {
    expect((await call()).isSuccess(), isTrue);
    when(() => repository.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(record(revoked: true)));
    expect((await call()).isError(), isTrue);
  });
  test('requires local identity, agent binding, explicit io and operation scopes', () async {
    for (final denied in [
      record(client: ''),
      record(agent: null),
      record(agent: 'other'),
      record(payload: {}),
      record(
        payload: {
          'agent_action_scopes': ['agent_actions.run'],
        },
      ),
      record(
        payload: {
          'agent_action_scopes': ['agent_actions.io'],
        },
      ),
      record(
        payload: {
          'agent_actions': {
            'scopes': ['agent_actions.*'],
            'action_ids': ['other'],
          },
        },
      ),
    ]) {
      when(() => repository.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Success(denied));
      expect((await call()).isError(), isTrue);
    }
  });
  test('wildcard remains explicit and ownership remains mandatory', () async {
    when(() => repository.getTokenPolicySummaryByHash(any())).thenAnswer(
      (_) async => Success(
        record(
          payload: {
            'agent_action_scopes': ['agent_actions.*'],
          },
        ),
      ),
    );
    expect((await call(owner: 'client')).isSuccess(), isTrue);
    expect((await call(owner: 'other')).isError(), isTrue);
  });
  test('local lookup failure is preserved without JWT fallback', () async {
    final failure = domain.DatabaseFailure('unavailable');
    when(() => repository.getTokenPolicySummaryByHash(any())).thenAnswer((_) async => Failure(failure));
    expect((await call()).exceptionOrNull(), same(failure));
  });
  test('locally matched JWT must also satisfy its lifetime', () async {
    String jwt(Map<String, dynamic> claims) => 'e30.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.signature';
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    expect((await call(credential: jwt({'exp': seconds}))).isError(), isTrue);
    expect((await call(credential: jwt({'nbf': seconds + 1}))).isError(), isTrue);
    expect((await call(credential: jwt({'exp': 'invalid'}))).isError(), isTrue);
    expect((await call(credential: jwt({'exp': seconds + 60, 'nbf': seconds}))).isSuccess(), isTrue);
  });
}
