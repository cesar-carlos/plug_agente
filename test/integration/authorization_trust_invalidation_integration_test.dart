import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/services/authorization_trust_invalidator.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:result_dart/result_dart.dart';

class _ConfigRepository extends Mock implements IAgentConfigRepository {}

class _Flags extends Mock implements FeatureFlags {}

void main() {
  final keyA = JsonWebKey.generate('ES256');
  final keyB = JsonWebKey.generate('ES256');
  const policy = ClientTokenPolicy(
    clientId: 'client',
    allTables: true,
    allViews: true,
    allPermissions: true,
    rules: [],
  );
  Config config(String id, String server) => Config(
    id: id,
    agentId: 'agent',
    serverUrl: server,
    driverName: 'SQL Server',
    odbcDriverName: 'SQL Server',
    connectionString: '',
    username: 'user',
    databaseName: 'db',
    host: 'localhost',
    port: 1433,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  String sign(JsonWebKey key) {
    final builder = JsonWebSignatureBuilder()..jsonContent = {'policy': policy.toJson()};
    builder.addRecipient(key, algorithm: 'ES256');
    return builder.build().toCompactSerialization();
  }

  final tokenA = sign(keyA);
  final tokenB = sign(keyB);
  late DateTime now;
  late Map<String, Config> configs;
  late _ConfigRepository repository;
  late InMemoryAppSettingsStore settings;
  late ActiveConfigResolver active;
  late SaveAgentConfig save;
  late ClientTokenPolicyMemoryCache policies;
  late InMemoryAuthorizationDecisionCache decisions;
  late JwtJwksVerifier verifier;
  late AuthorizationPolicyResolver resolver;
  late AuthorizeSqlOperation authorize;
  _PausedKeyStore? nextLookup;
  var failLoads = false;

  setUpAll(() => registerFallbackValue(config('fallback', 'https://hub-a.invalid')));
  setUp(() {
    now = DateTime.utc(2026, 10, 8);
    configs = {'a': config('a', 'https://hub-a.invalid'), 'b': config('b', 'https://hub-b.invalid')};
    repository = _ConfigRepository();
    when(
      () => repository.getById(any()),
    ).thenAnswer((call) async => Success(configs[call.positionalArguments.single]!));
    when(
      () => repository.getByIdMetadata(any()),
    ).thenAnswer((call) async => Success(configs[call.positionalArguments.single]!));
    when(() => repository.getCurrentConfigMetadata()).thenAnswer((_) async => Success(configs['b']!));
    when(() => repository.save(any())).thenAnswer((call) async {
      final saved = call.positionalArguments.single as Config;
      configs[saved.id] = saved;
      return Success(saved);
    });
    settings = InMemoryAppSettingsStore({AppConstants.activeConfigIdSettingsKey: 'a'});
    policies = ClientTokenPolicyMemoryCache(now: () => now);
    decisions = InMemoryAuthorizationDecisionCache(now: () => now);
    nextLookup = null;
    failLoads = false;
    verifier = JwtJwksVerifier(
      () async {
        final current = (await active.resolveActiveOrFallback(metadataOnly: true, persistFallback: false)).getOrThrow();
        return JwksConfig(jwksUrl: '${current.serverUrl}/jwks');
      },
      failureThreshold: 1,
      circuitOpenDuration: const Duration(seconds: 10),
      now: () => now,
      createKeyStore: (uri) {
        if (nextLookup != null) {
          final paused = nextLookup!;
          nextLookup = null;
          return paused;
        }
        return failLoads
            ? _UnavailableKeyStore()
            : (JsonWebKeyStore()..addKey(uri.host == 'hub-a.invalid' ? keyA : keyB));
      },
    );
    final invalidator = AuthorizationTrustInvalidator(
      decisionCache: decisions,
      policyCache: policies,
      verifier: verifier,
    );
    active = ActiveConfigResolver(repository, settings, authorizationTrustInvalidator: invalidator);
    save = SaveAgentConfig(repository, ConfigService(ConfigValidator()), authorizationTrustInvalidator: invalidator);
    final flags = _Flags();
    when(() => flags.enableSocketJwksValidation).thenReturn(true);
    when(() => flags.enableSocketRevokedTokenInSession).thenReturn(false);
    resolver = AuthorizationPolicyResolver(flags, jwksVerifier: verifier, policyCache: policies);
    authorize = AuthorizeSqlOperation(
      SqlOperationClassifier(),
      ClientTokenValidationService(resolver, now: () => now),
      decisionCache: decisions,
      now: () => now,
    );
  });

  Future<void> warm() async {
    expect((await authorize(token: tokenA, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
    expect(policies.get(hashClientCredentialToken(tokenA)), isNotNull);
  }

  Future<void> expectNewTrust() async {
    expect(policies.get(hashClientCredentialToken(tokenA)), isNull);
    expect((await authorize(token: tokenA, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
    expect((await authorize(token: tokenB, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  }

  test('saving a different server clears both policy and SQL decision caches', () async {
    await warm();
    final revision = decisions.revision;
    expect((await save(configs['a']!.copyWith(serverUrl: configs['b']!.serverUrl))).isSuccess(), isTrue);
    expect(decisions.revision, greaterThan(revision));
    await expectNewTrust();
  });

  test('switching the active profile removes the previous trust immediately', () async {
    await warm();
    await active.setActiveConfigId('b');
    await expectNewTrust();
  });

  test('clearing the active profile revalidates the fallback server', () async {
    await warm();
    await active.clearActiveConfigId();
    await expectNewTrust();
  });

  test('unchanged active profile preserves valid caches', () async {
    await warm();
    final revision = decisions.revision;
    await active.setActiveConfigId('a');
    expect(decisions.revision, revision);
    expect(policies.get(hashClientCredentialToken(tokenA)), isNotNull);
    expect((await authorize(token: tokenA, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  });

  test('failed config persistence preserves the current trust', () async {
    await warm();
    final revision = decisions.revision;
    when(
      () => repository.save(any()),
    ).thenAnswer((_) async => Failure(domain.DatabaseFailure('injected persistence failure')));
    expect((await save(configs['a']!.copyWith(serverUrl: configs['b']!.serverUrl))).isError(), isTrue);
    expect(decisions.revision, revision);
    expect(policies.get(hashClientCredentialToken(tokenA)), isNotNull);
    expect((await authorize(token: tokenA, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  });

  for (final failOldLookup in [false, true]) {
    test('pending JWKS ${failOldLookup ? 'failure' : 'success'} cannot revive the previous trust', () async {
      final paused = _PausedKeyStore(JsonWebKeyStore()..addKey(keyA), fail: failOldLookup);
      nextLookup = paused;
      final pending = authorize(token: tokenA, sql: 'SELECT * FROM dbo.users');
      await paused.started.future;
      expect((await save(configs['a']!.copyWith(serverUrl: configs['b']!.serverUrl))).isSuccess(), isTrue);
      paused.release.complete();
      expect((await pending).isError(), isTrue);
      await expectNewTrust();
    });
  }

  test('switching profiles resets the circuit of the previous server', () async {
    failLoads = true;
    final failed = (await verifier.verify(tokenA)).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(failed.isTransient, isTrue);
    final blocked = (await verifier.verify(tokenA)).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(blocked.context['reason'], AuthorizationContextConstants.jwksCircuitOpenReason);
    failLoads = false;
    await active.setActiveConfigId('b');
    expect((await verifier.verify(tokenB)).isSuccess(), isTrue);
  });

  test('temporary JWKS unavailability is not retained as a SQL denial', () async {
    failLoads = true;
    expect((await authorize(token: tokenA, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
    failLoads = false;
    now = now.add(const Duration(seconds: 10));
    expect((await authorize(token: tokenA, sql: 'SELECT * FROM dbo.users')).isSuccess(), isTrue);
  });
}

class _PausedKeyStore extends JsonWebKeyStore {
  _PausedKeyStore(this.delegate, {required this.fail});
  final JsonWebKeyStore delegate;
  final bool fail;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Stream<JsonWebKey?> findJsonWebKeys(JoseHeader header, String operation) async* {
    started.complete();
    await release.future;
    if (fail) throw const SocketException('injected old JWKS failure');
    await for (final key in delegate.findJsonWebKeys(header, operation)) {
      yield key;
    }
  }
}

class _UnavailableKeyStore extends JsonWebKeyStore {
  @override
  Stream<JsonWebKey?> findJsonWebKeys(JoseHeader header, String operation) =>
      Stream.error(const SocketException('injected key load failure'));
}
