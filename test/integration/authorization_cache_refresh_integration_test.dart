import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:result_dart/result_dart.dart';

import '../helpers/memory_token_secret_store.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockTokens extends Mock implements IClientTokenRepository {}

FeatureFlags _flags() {
  final value = _MockFeatureFlags();
  when(() => value.enableSocketJwksValidation).thenReturn(false);
  when(() => value.enableSocketRevokedTokenInSession).thenReturn(false);
  return value;
}

void main() {
  const initial = ClientTokenCreateRequest(
    clientId: 'old',
    agentId: 'agent-old',
    payload: {'label': 'old'},
    allTables: false,
    allViews: false,
    rules: [],
  );
  const edited = ClientTokenCreateRequest(
    clientId: 'new',
    agentId: 'agent-new',
    payload: {'label': 'new'},
    allTables: false,
    allViews: false,
    rules: [],
  );
  late AppDatabase database;
  late ClientTokenLocalDataSource source;
  late ClientTokenPolicyMemoryCache policies;
  late InMemoryAuthorizationDecisionCache decisions;
  late MemoryTokenSecretStore secrets;
  late ClientTokenRepository repository;
  late AuthorizationPolicyResolver resolver;
  late String token;
  late String id;

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    source = ClientTokenLocalDataSource(database);
    policies = ClientTokenPolicyMemoryCache();
    decisions = InMemoryAuthorizationDecisionCache();
    secrets = MemoryTokenSecretStore();
    repository = ClientTokenRepository(source, secretStore: secrets, policyCache: policies, decisionCache: decisions);
    resolver = AuthorizationPolicyResolver(_flags(), clientTokenRepository: repository, policyCache: policies);
    token = (await repository.createToken(initial)).getOrThrow();
    id = (await source.listTokens()).single.id;
  });
  tearDown(() async => database.close());

  test('metadata edit refreshes introspection and cached denial identity without rotating secrets', () async {
    final introspect = GetClientTokenPolicy(resolver);
    final authorize = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      ClientTokenValidationService(resolver),
      decisionCache: decisions,
    );
    final before = (await introspect(token)).getOrThrow();
    for (var attempt = 0; attempt < 2; attempt++) {
      final denied =
          (await authorize(token: token, sql: 'SELECT * FROM dbo.users')).exceptionOrNull()!
              as domain.ConfigurationFailure;
      expect(denied.context['client_id'], 'old');
    }
    final originalSecrets = Map<String, String>.from(secrets.values);
    secrets.reads = 0;
    final updated = (await repository.updateToken(id, edited)).getOrThrow();
    expect(updated.outcome, ClientTokenUpdateOutcome.metadataOnly);
    expect(updated.tokenValue, isNull);
    expect(secrets.values, originalSecrets);
    expect(secrets.reads, 0);
    expect((await source.findRowById(id))!.tokenHash, hashClientCredentialToken(token));
    final after = (await introspect(token)).getOrThrow();
    expect(after.clientId, 'new');
    expect(after.agentId, 'agent-new');
    expect(after.payload['label'], 'new');
    expect(after.tokenUpdatedAt, (await source.findRowById(id))!.updatedAt);
    expect(after.issuedAt, before.issuedAt);
    expect(updated.version, 2);
    for (var attempt = 0; attempt < 2; attempt++) {
      final denied =
          (await authorize(token: token, sql: 'SELECT * FROM dbo.users')).exceptionOrNull()!
              as domain.ConfigurationFailure;
      expect(denied.context['client_id'], 'new');
    }
  });

  test('metadata edit invalidates pending policy snapshots', () async {
    final hash = hashClientCredentialToken(token);
    final oldPolicy = (await resolver.resolvePolicy(token)).getOrThrow();
    policies.invalidate(hash);
    final lookup = Completer<Result<ClientTokenPolicy>>();
    final pending = policies.resolveSingleFlight(hash, () => lookup.future);
    try {
      (await repository.updateToken(id, edited)).getOrThrow();
      lookup.complete(Success(oldPolicy));
      expect((await pending).isCurrent, isFalse);
      expect((await resolver.resolvePolicy(token)).getOrThrow().clientId, 'new');
    } finally {
      if (!lookup.isCompleted) lookup.complete(Success(oldPolicy));
      await pending;
    }
  });

  test('no-op and failed metadata edits preserve valid caches', () async {
    final before = (await resolver.resolvePolicy(token)).getOrThrow();
    final revision = decisions.revision;
    final unchanged = (await repository.updateToken(id, initial)).getOrThrow();
    expect(unchanged.outcome, ClientTokenUpdateOutcome.unchanged);
    expect((await repository.updateToken(id, edited, expectedVersion: 99)).isError(), isTrue);
    expect((await resolver.resolvePolicy(token)).getOrThrow(), same(before));
    expect(decisions.revision, revision);
  });

  for (final legacy in [false, true]) {
    for (final transient in [false, true]) {
      test(
        'local DB failure preserves retry behavior through SQL cache (legacy=$legacy, transient=$transient)',
        () async {
          final tokens = _MockTokens();
          var lookups = 0;
          final cause = Exception('local store unavailable');
          final storageFailure = legacy
              ? domain.ServerFailure.withContext(
                  message: 'database unavailable',
                  cause: cause,
                  context: {'transient': transient, 'operation': 'read_policy'},
                )
              : domain.DatabaseFailure.withContext(
                  message: 'database busy',
                  cause: cause,
                  context: {'retryable': transient, 'operation': 'read_policy'},
                );
          when(() => tokens.getTokenPolicySummaryByHash(any())).thenAnswer((_) async {
            lookups++;
            return lookups == 1
                ? Failure(storageFailure)
                : Success(
                    ClientTokenSummary(
                      id: 'id',
                      clientId: 'c',
                      createdAt: DateTime.utc(2026),
                      isRevoked: false,
                      allTables: true,
                      allViews: true,
                      allPermissions: true,
                      rules: const [],
                    ),
                  );
          });
          final policyResolver = AuthorizationPolicyResolver(
            _flags(),
            clientTokenRepository: tokens,
            policyCache: policies,
          );
          final authorize = AuthorizeSqlOperation(
            SqlOperationClassifier(),
            ClientTokenValidationService(policyResolver),
            decisionCache: decisions,
          );
          final failure =
              (await authorize(token: 'opaque', sql: 'SELECT * FROM dbo.users')).exceptionOrNull()!
                  as domain.ConfigurationFailure;
          expect(failure.isTransient, transient);
          expect(failure.cause, same(cause));
          expect(failure.context['operation'], 'read_policy');
          expect(failure.context['user_message'], contains('armazenamento local'));
          expect((await authorize(token: 'opaque', sql: 'SELECT * FROM dbo.users')).isSuccess(), transient);
          expect(lookups, transient ? 2 : 1);
        },
      );
    }
  }
}
