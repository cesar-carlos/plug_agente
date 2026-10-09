import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler_idempotency_orchestrator.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:result_dart/result_dart.dart';

class _Flags extends Mock implements FeatureFlags {}

class _Tokens extends Mock implements IClientTokenRepository {}

void main() {
  final key = JsonWebKey.generate('ES256');
  late _Flags flags;
  late AuthorizationPolicyResolver resolver;
  late AuthorizeSqlOperation authorize;
  late AgentActionRemoteAuthorizationService remote;
  setUp(() {
    flags = _Flags();
    when(() => flags.enableSocketJwksValidation).thenReturn(true);
    when(() => flags.enableSocketRevokedTokenInSession).thenReturn(false);
    when(() => flags.enableClientTokenAuthorization).thenReturn(true);
    when(() => flags.enableSocketTimeoutByStage).thenReturn(false);
    resolver = AuthorizationPolicyResolver(
      flags,
      jwksVerifier: JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
        createKeyStore: (_) => JsonWebKeyStore()..addKey(key),
      ),
      policyCache: ClientTokenPolicyMemoryCache(),
    );
    authorize = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      ClientTokenValidationService(resolver),
      decisionCache: InMemoryAuthorizationDecisionCache(),
    );
    remote = AgentActionRemoteAuthorizationService(
      featureFlags: flags,
      getClientTokenPolicy: GetClientTokenPolicy(resolver),
      authorizeSqlOperation: authorize,
    );
  });
  String sign(Map<String, dynamic> policy) {
    final builder = JsonWebSignatureBuilder()..jsonContent = {'policy': policy};
    builder.addRecipient(key, algorithm: 'ES256');
    return builder.build().toCompactSerialization();
  }

  Future<({RpcResponse? denied, ClientTokenPolicy? policy})> runRemote(String token) => remote.authorizeIfNeeded(
    request: const RpcRequest(jsonrpc: '2.0', id: 1, method: 'agent.action.run'),
    clientToken: token,
    authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionRun,
    requiredAgentActionScope: AgentActionRpcConstants.agentActionsRunScope,
    actionIdForAllowlist: 'allowed-action',
  );

  final malformed = <Map<String, dynamic>>[
    {'database': 42},
    {'database': ''},
    {'database': null},
    {'agent_actions': 'invalid'},
    {'agent_actions': null},
    {
      'token_scope': [42],
    },
    {'agent_action_scopes': false},
    {
      'agent_actions': {
        'scopes': [42],
      },
    },
    {
      'agent_actions': {
        'scopes': ['agent_actions.run'],
        'action_ids': 'allowed-action',
      },
    },
    {
      'agent_actions': {
        'scopes': ['agent_actions.run'],
        'action_ids': ['allowed-action', 42],
      },
    },
  ];
  for (var i = 0; i < malformed.length; i++) {
    test('signed malformed runtime restrictions $i cannot authorize SQL or remote actions', () async {
      final token = sign({
        'client_id': 'client',
        'all_permissions': true,
        'payload': malformed[i],
        'rules': <Map<String, dynamic>>[],
      });
      final policyResult = await GetClientTokenPolicy(resolver)(token);
      final failure = policyResult.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.invalidPolicyReason);
      expect(failure.context['user_message'], isNotEmpty);
      expect(
        (await authorize(token: token, sql: 'SELECT * FROM dbo.users', requestDatabase: 'unrelated')).isError(),
        isTrue,
      );
      expect((await runRemote(token)).denied, isNotNull);
    });
  }
  test('a malformed signed deny rule fails the entire policy instead of becoming an allow', () async {
    final token = sign({
      'client_id': 'client',
      'all_tables': false,
      'all_views': false,
      'rules': [
        {'effect': 'deny_typo', 'resource_type': 'table', 'resource': 'dbo.users', 'read': true},
      ],
    });
    final failure =
        (await authorize(token: token, sql: 'SELECT * FROM dbo.users')).exceptionOrNull()!
            as domain.ConfigurationFailure;
    expect(failure.context['reason'], AuthorizationContextConstants.invalidPolicyReason);
  });
  test('valid database, scopes and action allowlist still constrain a signed token', () async {
    final token = sign({
      'client_id': 'client',
      'all_permissions': true,
      'payload': {'database': 'ERP'},
      'rules': <Map<String, dynamic>>[],
    });
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users', requestDatabase: 'ERP')).isSuccess(), isTrue);
    expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users', requestDatabase: 'other')).isError(), isTrue);
    final actionToken = sign({
      'client_id': 'client',
      'all_permissions': true,
      'payload': {
        'agent_actions': {
          'scopes': ['agent_actions.run'],
          'action_ids': ['allowed-action'],
        },
      },
      'rules': <Map<String, dynamic>>[],
    });
    expect((await runRemote(actionToken)).denied, isNull);
  });
  test('valid legacy signed policy retains remote compatibility', () async {
    final token = sign({'client_id': 'client', 'all_permissions': true, 'rules': <Map<String, dynamic>>[]});
    expect((await runRemote(token)).denied, isNull);
  });
  test('malformed local stored restrictions cannot be authorized either', () async {
    final tokens = _Tokens();
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer(
      (_) async => Success(
        ClientTokenSummary(
          id: 'local',
          clientId: 'client',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: true,
          allPermissions: true,
          rules: const [],
          payload: const {'database': 42},
        ),
      ),
    );
    final localResolver = AuthorizationPolicyResolver(flags, clientTokenRepository: tokens);
    final failure = (await localResolver.resolvePolicy('opaque')).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(failure.context['reason'], AuthorizationContextConstants.invalidPolicyReason);
  });
  test('RPC timeouts retain bounded backing work and retries recover without cached transient denial', () async {
    final pending = <Completer<Result<ClientTokenSummary>>>[];
    final tokens = _Tokens();
    var stalled = true;
    final summary = ClientTokenSummary(
      id: 'id',
      clientId: 'client',
      createdAt: DateTime.utc(2026),
      isRevoked: false,
      allTables: true,
      allViews: true,
      allPermissions: true,
      rules: const [],
    );
    when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) {
      if (!stalled) return Future.value(Success(summary));
      final completion = Completer<Result<ClientTokenSummary>>();
      pending.add(completion);
      return completion.future;
    });
    final cache = ClientTokenPolicyMemoryCache(maxEntries: 2, resolutionTimeout: const Duration(milliseconds: 50));
    final policyResolver = AuthorizationPolicyResolver(flags, clientTokenRepository: tokens, policyCache: cache);
    final sql = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      ClientTokenValidationService(policyResolver),
      decisionCache: InMemoryAuthorizationDecisionCache(),
    );
    final budget = RpcMethodHandlerIdempotencyOrchestrator(
      authorizeSqlOperation: sql,
      featureFlags: flags,
      authorizationStageBudget: const Duration(milliseconds: 10),
    );
    try {
      for (var i = 0; i < 20; i++) {
        final result = await budget.authorizeWithBudget(
          token: 'unique-$i',
          sql: 'SELECT * FROM dbo.users',
          requestDatabase: null,
          requestId: '$i',
          method: 'sql.execute',
          deadline: DateTime.now().add(const Duration(seconds: 1)),
        );
        expect(result.isError(), isTrue);
        if (i >= 2) {
          final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;
          expect(failure.context['reason'], AuthorizationContextConstants.policyResolutionBusyReason);
          expect(failure.isTransient, isTrue);
        }
      }
      expect(pending, hasLength(2));
    } finally {
      stalled = false;
      for (final completion in pending) {
        completion.complete(Success(summary));
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect((await sql(token: 'unique-3', sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  });
}
