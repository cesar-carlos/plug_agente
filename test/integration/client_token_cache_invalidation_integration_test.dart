import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:result_dart/result_dart.dart';

import '../helpers/memory_token_secret_store.dart';

void main() {
  late AppDatabase database;
  late _PausedRevocationSource source;
  late _ControlledSecretStore secrets;
  late ClientTokenRepository repository;
  late ClientTokenPolicyMemoryCache policies;
  late InMemoryAuthorizationDecisionCache decisions;
  late RevokeClientToken revoke;
  late DeleteClientToken delete;
  late UpdateClientToken update;
  late String tokenId;
  late String token;
  late String hash;

  const request = ClientTokenCreateRequest(
    clientId: 'client',
    allTables: true,
    allViews: false,
    globalPermissions: ClientPermissionSet.fullAccess,
    rules: [],
  );
  const rotationRequest = ClientTokenCreateRequest(
    clientId: 'client',
    allTables: true,
    allViews: true,
    globalPermissions: ClientPermissionSet.fullAccess,
    rules: [],
  );
  const policy = ClientTokenPolicy(
    clientId: 'client',
    allTables: true,
    allViews: true,
    allPermissions: true,
    rules: [],
  );

  void cache(String credentialHash) {
    policies.put(credentialHash, policy);
    decisions.put(
      '$credentialHash|sql',
      AuthorizationDecisionCacheEntry(
        allowed: true,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ),
    );
  }

  void expectInvalidated(String credentialHash) {
    expect(policies.get(credentialHash), isNull);
    expect(decisions.get('$credentialHash|sql'), isNull);
  }

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    source = _PausedRevocationSource(database);
    secrets = _ControlledSecretStore();
    policies = ClientTokenPolicyMemoryCache();
    decisions = InMemoryAuthorizationDecisionCache();
    repository = ClientTokenRepository(source, secretStore: secrets, policyCache: policies, decisionCache: decisions);
    revoke = RevokeClientToken(repository);
    delete = DeleteClientToken(repository);
    update = UpdateClientToken(repository);
    token = (await CreateClientToken(repository)(request)).getOrThrow();
    tokenId = (await source.listTokens()).single.id;
    hash = hashClientCredentialToken(token);
    cache(hash);
    cache('unrelated');
    secrets.reads = 0;
  });
  tearDown(() async => database.close());

  for (final action in ['revoke', 'delete', 'metadata']) {
    test('$action does not read secrets to manage authorization caches', () async {
      switch (action) {
        case 'revoke':
          expect((await revoke(tokenId)).isSuccess(), isTrue);
        case 'delete':
          expect((await delete(tokenId)).isSuccess(), isTrue);
        case 'metadata':
          expect(
            (await update(
              tokenId,
              const ClientTokenCreateRequest(
                clientId: 'client',
                name: 'renamed',
                allTables: true,
                allViews: false,
                globalPermissions: ClientPermissionSet.fullAccess,
                rules: [],
              ),
            )).isSuccess(),
            isTrue,
          );
      }
      expect(secrets.reads, 0);
      expect(policies.get('unrelated'), isNotNull);
      expect(decisions.get('unrelated|sql'), isNotNull);
      expectInvalidated(hash);
    });
  }

  for (final action in ['delete', 'rotate']) {
    test('$action invalidates committed hashes and pending resolutions before secret cleanup', () async {
      secrets.blockDeletion = true;
      String? newHash;
      secrets.onSaved = (key) {
        newHash = key;
        cache(key);
      };
      final lookup = Completer<Result<ClientTokenPolicy>>();
      final pending = policies.resolveSingleFlight(hash, () => lookup.future);
      final mutation = action == 'delete' ? delete(tokenId) : update(tokenId, rotationRequest);
      await secrets.deletionStarted.future;
      try {
        final row = await source.findRowById(tokenId);
        expect(row == null || row.tokenHash != hash, isTrue);
        expectInvalidated(hash);
        if (newHash != null) expectInvalidated(newHash!);
        lookup.complete(const Success(policy));
        expect((await pending).isCurrent, isFalse);
        expect(policies.get('unrelated'), isNotNull);
      } finally {
        if (!lookup.isCompleted) lookup.complete(const Success(policy));
        secrets.releaseDeletion.complete();
        await mutation;
        await pending;
      }
    });
  }

  test('revocation invalidates the credential rotated while the mutation waits', () async {
    source.pauseRevocation = true;
    final revoking = revoke(tokenId);
    await source.revocationStarted.future;
    try {
      final rotated = (await update(tokenId, rotationRequest)).getOrThrow();
      final rotatedHash = hashClientCredentialToken(rotated.tokenValue!);
      cache(rotatedHash);
      source.releaseRevocation.complete();
      expect((await revoking).isSuccess(), isTrue);
      expect((await source.findRowById(tokenId))!.isRevoked, isTrue);
      expectInvalidated(rotatedHash);
      expect(policies.get('unrelated'), isNotNull);
    } finally {
      if (!source.releaseRevocation.isCompleted) source.releaseRevocation.complete();
      await revoking;
    }
  });

  test('new token invalidates preexisting resolutions for its committed hash', () async {
    String? createdHash;
    secrets.onSaved = (key) {
      createdHash = key;
      cache(key);
    };
    expect((await CreateClientToken(repository)(request)).isSuccess(), isTrue);
    expectInvalidated(createdHash!);
    expect(policies.get(hash), isNotNull);
  });

  for (final action in ['delete', 'rotate']) {
    test('$action preserves success and invalidation when secret cleanup fails', () async {
      secrets.failDelete = true;
      final result = action == 'delete' ? await delete(tokenId) : await update(tokenId, rotationRequest);
      expect(result.isSuccess(), isTrue);
      expectInvalidated(hash);
      expect(policies.get('unrelated'), isNotNull);
      expect(decisions.get('unrelated|sql'), isNotNull);
    });
  }

  ClientTokenSummary replacement() => ClientTokenSummary(
    id: tokenId,
    clientId: 'replacement',
    tokenValue: 'replacement-token',
    createdAt: DateTime.utc(2026),
    isRevoked: false,
    allTables: true,
    allViews: false,
    rules: const [],
  );

  test('replacement invalidates all cached and pending policies before obsolete secret cleanup', () async {
    secrets.blockDeletion = true;
    final lookup = Completer<Result<ClientTokenPolicy>>();
    final pending = policies.resolveSingleFlight('unrelated', () => lookup.future);
    final mutation = repository.replaceTokens([replacement()]);
    await secrets.deletionStarted.future;
    try {
      expect((await source.findRowById(tokenId))!.clientId, 'replacement');
      expectInvalidated(hash);
      expectInvalidated('unrelated');
      lookup.complete(const Success(policy));
      expect((await pending).isCurrent, isFalse);
    } finally {
      if (!lookup.isCompleted) lookup.complete(const Success(policy));
      secrets.releaseDeletion.complete();
      await mutation;
      await pending;
    }
  });

  test('failed replacement preserves persisted tokens and their authorization caches', () async {
    secrets.failWrite = true;
    await expectLater(repository.replaceTokens([replacement()]), throwsA(isA<domain.ConfigurationFailure>()));
    expect((await source.findRowById(tokenId))!.tokenHash, hash);
    expect(policies.get(hash), same(policy));
    expect(decisions.get('$hash|sql'), isNotNull);
    expect(policies.get('unrelated'), isNotNull);
    expect(secrets.values[hash], token);
  });

  for (final action in ['revoke', 'delete', 'rotate', 'replace']) {
    test('$action prevents an already resolved policy from repopulating SQL decision cache', () async {
      final flags = _MockFeatureFlags();
      when(() => flags.enableSocketJwksValidation).thenReturn(false);
      when(() => flags.enableSocketRevokedTokenInSession).thenReturn(false);
      final paused = _PausedPolicyResolver(
        AuthorizationPolicyResolver(
          flags,
          clientTokenRepository: repository,
          policyCache: policies,
        ),
      );
      final authorize = AuthorizeSqlOperation(
        SqlOperationClassifier(),
        ClientTokenValidationService(paused),
        decisionCache: decisions,
      );
      final authorization = authorize(token: token, sql: 'SELECT * FROM dbo.users');
      await paused.snapshotResolved.future;
      try {
        switch (action) {
          case 'revoke':
            (await revoke(tokenId)).getOrThrow();
          case 'delete':
            (await delete(tokenId)).getOrThrow();
          case 'rotate':
            (await update(tokenId, rotationRequest)).getOrThrow();
          case 'replace':
            await repository.replaceTokens([replacement()]);
        }
        paused.releaseSnapshot.complete();
        final result = await authorization;
        expect(result.exceptionOrNull(), isA<domain.ConfigurationFailure>());
        expect((await authorize(token: token, sql: 'SELECT * FROM dbo.users')).isError(), isTrue);
        expect(policies.get(hash), isNull);
      } finally {
        if (!paused.releaseSnapshot.isCompleted) paused.releaseSnapshot.complete();
        await authorization;
      }
    });
  }

  test('secure storage failure preserves previously valid caches', () async {
    secrets.failWrite = true;
    final result = await update(tokenId, rotationRequest);
    expect(result.exceptionOrNull(), isA<domain.ConfigurationFailure>());
    expect(policies.get(hash), same(policy));
    expect(decisions.get('$hash|sql'), isNotNull);
    expect((await source.findRowById(tokenId))!.tokenHash, hash);
  });

  test('version conflict and missing mutations preserve caches', () async {
    expect(
      (await update(tokenId, rotationRequest, expectedVersion: 99)).exceptionOrNull(),
      isA<domain.ValidationFailure>(),
    );
    expect((await revoke('missing')).isError(), isTrue);
    expect((await delete('missing')).isError(), isTrue);
    expect(policies.get(hash), same(policy));
    expect(decisions.get('$hash|sql'), isNotNull);
    expect(secrets.reads, 0);
  });
}

class _ControlledSecretStore extends MemoryTokenSecretStore {
  bool blockDeletion = false;
  bool failDelete = false;
  final deletionStarted = Completer<void>();
  final releaseDeletion = Completer<void>();
  void Function(String key)? onSaved;

  @override
  Future<void> saveSecret(String secretKey, String tokenValue) async {
    await super.saveSecret(secretKey, tokenValue);
    onSaved?.call(secretKey);
  }

  @override
  Future<void> deleteSecret(String secretKey) async {
    if (blockDeletion) {
      blockDeletion = false;
      deletionStarted.complete();
      await releaseDeletion.future;
    }
    if (failDelete) throw Exception('injected cleanup failure');
    await super.deleteSecret(secretKey);
  }
}

class _PausedRevocationSource extends ClientTokenLocalDataSource {
  _PausedRevocationSource(super._database);

  bool pauseRevocation = false;
  final revocationStarted = Completer<void>();
  final releaseRevocation = Completer<void>();

  @override
  Future<ClientTokenCacheData?> revokeTokenRow(String tokenId) async {
    await _pause();
    return super.revokeTokenRow(tokenId);
  }

  Future<void> _pause() async {
    if (!pauseRevocation) return;
    pauseRevocation = false;
    revocationStarted.complete();
    await releaseRevocation.future;
  }
}

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _PausedPolicyResolver implements IAuthorizationPolicyResolver {
  _PausedPolicyResolver(this.delegate);
  final IAuthorizationPolicyResolver delegate;
  final snapshotResolved = Completer<void>();
  final releaseSnapshot = Completer<void>();

  @override
  Future<Result<ClientTokenPolicy>> resolvePolicy(String token) async {
    final result = await delegate.resolvePolicy(token);
    if (!snapshotResolved.isCompleted) {
      snapshotResolved.complete();
      await releaseSnapshot.future;
    }
    return result;
  }
}
