import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:result_dart/result_dart.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockAuthorize extends Mock implements AuthorizeSqlOperation {}

void main() {
  final key = JsonWebKey.generate('ES256');
  late DateTime now;
  late _MockFeatureFlags flags;
  late AuthorizationPolicyResolver resolver;
  late AuthorizeSqlOperation authorize;
  late ClientTokenPolicyMemoryCache policies;
  late InMemoryAuthorizationDecisionCache decisions;

  String sign({num? exp, num? nbf}) {
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = <String, dynamic>{
        'policy': {
          'client_id': 'client',
          'all_tables': true,
          'all_views': true,
          'all_permissions': true,
          'rules': <Object>[],
        },
        'exp': ?exp,
        'nbf': ?nbf,
      };
    builder.addRecipient(key, algorithm: 'ES256');
    return builder.build().toCompactSerialization();
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 8);
    flags = _MockFeatureFlags();
    when(() => flags.enableSocketJwksValidation).thenReturn(true);
    when(() => flags.enableSocketRevokedTokenInSession).thenReturn(false);
    when(() => flags.enableClientTokenAuthorization).thenReturn(true);
    when(() => flags.enableSocketTimeoutByStage).thenReturn(false);
    policies = ClientTokenPolicyMemoryCache(now: () => now);
    decisions = InMemoryAuthorizationDecisionCache(now: () => now);
    resolver = AuthorizationPolicyResolver(
      flags,
      now: () => now,
      policyCache: policies,
      jwksVerifier: JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
        now: () => now,
        createKeyStore: (_) => JsonWebKeyStore()..addKey(key),
      ),
    );
    authorize = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      ClientTokenValidationService(resolver, now: () => now),
      decisionCache: decisions,
      now: () => now,
    );
  });

  for (final cache in ['policy', 'decision']) {
    test('$cache cache stops allowing a signed JWT at its expiration', () async {
      final expiration = now.add(const Duration(seconds: 10));
      final token = sign(exp: expiration.millisecondsSinceEpoch ~/ 1000);
      Future<Result<void>> check() async => cache == 'policy'
          ? (await resolver.resolvePolicy(token)).map((_) => unit)
          : await authorize(token: token, sql: 'SELECT * FROM dbo.users');
      expect((await check()).isSuccess(), isTrue);
      now = expiration.subtract(const Duration(microseconds: 1));
      expect((await check()).isSuccess(), isTrue);
      now = expiration;
      final failure = (await check()).exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.tokenExpiredReason);
      expect(failure.context['authentication'], isTrue);
    });
  }

  test('not-before rejection does not remain cached after the activation instant', () async {
    final activation = now.add(const Duration(seconds: 10));
    final token = sign(nbf: activation.millisecondsSinceEpoch ~/ 1000);
    final first = await authorize(token: token, sql: 'SELECT * FROM dbo.users');
    expect(
      (first.exceptionOrNull()! as domain.Failure).context['reason'],
      AuthorizationContextConstants.tokenNotYetValidReason,
    );
    now = activation;
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  });

  test('signed credentials without expiration preserve legacy authorization behavior', () async {
    final token = sign();
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
    now = now.add(const Duration(days: 1));
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  });

  for (final consumer in ['sql', 'policy', 'validation']) {
    test('$consumer rejects a policy that expires while its resolved snapshot waits', () async {
      final expiration = now.add(const Duration(seconds: 10));
      final token = sign(exp: expiration.millisecondsSinceEpoch ~/ 1000);
      final paused = _PausedResolver(resolver);
      Future<Result<void>> check() async {
        switch (consumer) {
          case 'sql':
            return AuthorizeSqlOperation(
              SqlOperationClassifier(),
              ClientTokenValidationService(paused, now: () => now),
              decisionCache: decisions,
              now: () => now,
            )(token: token, sql: 'SELECT * FROM dbo.users');
          case 'policy':
            return (await GetClientTokenPolicy(paused, now: () => now)(token)).map((_) => unit);
          default:
            return (await ClientTokenValidationService(paused, now: () => now).validate(token)).map((_) => unit);
        }
      }

      final pending = check();
      await paused.snapshotResolved.future;
      now = expiration;
      paused.releaseSnapshot.complete();
      final failure = (await pending).exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.tokenExpiredReason);
    });
  }

  test('SQL rejects expiration after validation has already succeeded', () async {
    final expiration = now.add(const Duration(seconds: 10));
    final token = sign(exp: expiration.millisecondsSinceEpoch ~/ 1000);
    final paused = _PausedValidationService(resolver, now: () => now);
    final service = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      paused,
      decisionCache: decisions,
      now: () => now,
    );
    final pending = service(token: token, sql: 'SELECT * FROM dbo.users');
    await paused.snapshotValidated.future;
    now = expiration;
    paused.releaseSnapshot.complete();
    final failure = (await pending).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(failure.context['reason'], AuthorizationContextConstants.tokenExpiredReason);
  });

  test('remote agent actions reject expiration while SQL authorization waits', () async {
    final expiration = now.add(const Duration(seconds: 10));
    final token = sign(exp: expiration.millisecondsSinceEpoch ~/ 1000);
    final started = Completer<void>();
    final permission = Completer<Result<void>>();
    final sqlAuthorization = _MockAuthorize();
    when(
      () => sqlAuthorization(
        token: any(named: 'token'),
        sql: any(named: 'sql'),
        requestId: any(named: 'requestId'),
        method: any(named: 'method'),
      ),
    ).thenAnswer((_) {
      started.complete();
      return permission.future;
    });
    final service = AgentActionRemoteAuthorizationService(
      now: () => now,
      featureFlags: flags,
      getClientTokenPolicy: GetClientTokenPolicy(resolver, now: () => now),
      authorizeSqlOperation: sqlAuthorization,
    );
    final pending = service.authorizeIfNeeded(
      request: const RpcRequest(jsonrpc: '2.0', id: 1, method: AgentActionRpcConstants.agentActionRunRpcMethodName),
      clientToken: token,
      authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionRun,
      requiredAgentActionScope: AgentActionRpcConstants.agentActionsRunScope,
      actionIdForAllowlist: 'action',
    );
    await started.future;
    now = expiration;
    permission.complete(const Success(unit));
    final result = await pending;
    expect(result.denied, isNotNull);
    expect(result.denied!.error!.code, RpcErrorCode.authenticationFailed);
    expect(
      (result.denied!.error!.data as Map<String, dynamic>)['reason'],
      RpcErrorCode.getReason(RpcErrorCode.authenticationFailed),
    );
  });
}

class _PausedResolver implements IAuthorizationPolicyResolver {
  _PausedResolver(this.delegate);
  final IAuthorizationPolicyResolver delegate;
  final snapshotResolved = Completer<void>();
  final releaseSnapshot = Completer<void>();
  @override
  Future<Result<ClientTokenPolicy>> resolvePolicy(String token) async {
    final snapshot = await delegate.resolvePolicy(token);
    snapshotResolved.complete();
    await releaseSnapshot.future;
    return snapshot;
  }
}

class _PausedValidationService extends ClientTokenValidationService {
  _PausedValidationService(super._resolver, {super.now});
  final snapshotValidated = Completer<void>();
  final releaseSnapshot = Completer<void>();
  @override
  Future<Result<ClientTokenPolicy>> validate(String token) async {
    final snapshot = await super.validate(token);
    snapshotValidated.complete();
    await releaseSnapshot.future;
    return snapshot;
  }
}
