import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_secret_store.dart';
import 'package:result_dart/result_dart.dart';

class MockClientTokenLocalDataSource extends Mock implements ClientTokenLocalDataSource {}

void main() {
  group('ClientTokenRepository (unit)', () {
    late MockClientTokenLocalDataSource mockDataSource;
    late ClientTokenRepository repository;

    setUp(() {
      mockDataSource = MockClientTokenLocalDataSource();
      repository = ClientTokenRepository(mockDataSource);
    });

    test('getTokenById returns Success when token exists', () async {
      const tokenId = 'token-1';
      final row = ClientTokenCacheData(
        id: tokenId,
        clientId: 'client-a',
        name: '',
        isRevoked: false,
        tokenValue: 'secret',
        createdAt: DateTime.utc(2026),
        version: 1,
        payloadJson: '{}',
        allTables: true,
        allViews: false,
        allPermissions: true,
        globalPermissionsJson: jsonEncode(ClientPermissionSet.fullAccess.toJson()),
        rulesJson: '[]',
        syncedAt: DateTime.utc(2026),
        tokenHash: 'hash',
      );
      when(() => mockDataSource.findRowById(tokenId)).thenAnswer((_) async => row);
      when(() => mockDataSource.mapRowToSummaryWithoutTokenValue(row)).thenReturn(
        ClientTokenSummary(
          id: tokenId,
          clientId: 'client-a',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: true,
          rules: const [],
        ),
      );

      final result = await repository.getTokenById(tokenId);

      expect(result.isSuccess(), isTrue);
      result.fold(
        (loaded) => expect(loaded.id, tokenId),
        (_) => fail('Expected success'),
      );
    });

    test('getTokenById returns NotFoundFailure when token is absent', () async {
      const tokenId = 'missing-token';
      when(() => mockDataSource.findRowById(tokenId)).thenAnswer((_) async => null);

      final result = await repository.getTokenById(tokenId);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.NotFoundFailure>()),
      );
    });

    test('getTokenById returns ServerFailure on datasource exception', () async {
      const tokenId = 'token-db-error';
      when(() => mockDataSource.findRowById(tokenId)).thenThrow(Exception('db down'));

      final result = await repository.getTokenById(tokenId);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ServerFailure>()),
      );
    });

    test('getTokenByHash returns Success when token exists', () async {
      const tokenHash = 'hash-abc';
      final row = ClientTokenCacheData(
        id: 'token-2',
        clientId: 'client-b',
        name: '',
        isRevoked: false,
        createdAt: DateTime.utc(2026),
        version: 1,
        payloadJson: '{}',
        allTables: false,
        allViews: false,
        allPermissions: false,
        globalPermissionsJson: jsonEncode(ClientPermissionSet.none.toJson()),
        rulesJson: '[]',
        syncedAt: DateTime.utc(2026),
        tokenHash: tokenHash,
      );
      when(() => mockDataSource.findRowByHash(tokenHash)).thenAnswer((_) async => row);
      when(() => mockDataSource.mapRowToSummaryWithoutTokenValue(row)).thenReturn(
        ClientTokenSummary(
          id: 'token-2',
          clientId: 'client-b',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: const [],
        ),
      );

      final result = await repository.getTokenByHash(tokenHash);

      expect(result.isSuccess(), isTrue);
      result.fold(
        (loaded) => expect(loaded.clientId, 'client-b'),
        (_) => fail('Expected success'),
      );
    });

    test('getTokenByHash returns NotFoundFailure when token is absent', () async {
      const tokenHash = 'hash-missing';
      when(() => mockDataSource.findRowByHash(tokenHash)).thenAnswer((_) async => null);

      final result = await repository.getTokenByHash(tokenHash);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.NotFoundFailure>()),
      );
    });

    test('getTokenByHash returns ServerFailure on datasource exception', () async {
      const tokenHash = 'hash-db-error';
      when(() => mockDataSource.findRowByHash(tokenHash)).thenThrow(Exception('db down'));

      final result = await repository.getTokenByHash(tokenHash);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ServerFailure>()),
      );
    });
  });

  group('ClientTokenRepository (integration)', () {
    ClientTokenCreateRequest baseRequest({String clientId = 'alpha'}) {
      return ClientTokenCreateRequest(
        clientId: clientId,
        allTables: true,
        allViews: false,
        allPermissions: true,
        rules: const [],
        payload: const {'k': 'v'},
        agentId: 'agent-1',
      );
    }

    Future<ClientTokenRepository> buildRepository({
      ITokenSecretStore? secretStore,
    }) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final dataSource = ClientTokenLocalDataSource(db);
      return ClientTokenRepository(
        dataSource,
        secretStore: secretStore,
      );
    }

    test('createToken returns token and getTokenById round-trips', () async {
      final repository = await buildRepository();

      final createResult = await repository.createToken(baseRequest());
      expect(createResult.isSuccess(), isTrue);
      final opaque = createResult.getOrNull()!;
      expect(opaque.length, 64);

      final listResult = await repository.listTokens();
      final byId = await repository.getTokenById(listResult.getOrNull()!.single.id);
      expect(byId.isSuccess(), isTrue);
      final summary = byId.getOrNull()!;
      expect(summary.clientId, 'alpha');
      expect(summary.tokenValue, opaque);
      expect(summary.agentId, 'agent-1');
      expect(summary.payload, const {'k': 'v'});

      final hash = repository.hashTokenForLookup(opaque);
      final byHash = await repository.getTokenByHash(hash);
      expect(byHash.getOrNull()!.id, summary.id);
    });

    test(
      'createToken persists payload.database and canonical global permissions while dropping resource rules in global mode',
      () async {
        final repository = await buildRepository();

        final createResult = await repository.createToken(
          const ClientTokenCreateRequest(
            clientId: 'global-client',
            allTables: true,
            allViews: false,
            globalPermissions: ClientPermissionSet(
              canRead: true,
              canUpdate: false,
              canDelete: false,
              canDdl: true,
            ),
            payload: {'database': 'ERP_MAIN', 'env': 'prod'},
            rules: [
              ClientTokenRule(
                resource: DatabaseResource(
                  resourceType: DatabaseResourceType.table,
                  name: 'dbo.should_be_discarded',
                ),
                permissions: ClientPermissionSet(
                  canRead: true,
                  canUpdate: true,
                  canDelete: false,
                ),
                effect: ClientTokenRuleEffect.allow,
              ),
            ],
          ),
        );

        final opaque = createResult.getOrNull()!;
        final listResult = await repository.listTokens();
        final byId = await repository.getTokenById(listResult.getOrNull()!.single.id);

        final summary = byId.getOrNull()!;
        expect(summary.tokenValue, opaque);
        expect(summary.payload, const {'database': 'ERP_MAIN', 'env': 'prod'});
        expect(summary.globalPermissions.canRead, isTrue);
        expect(summary.globalPermissions.canDdl, isTrue);
        expect(summary.globalPermissions.canUpdate, isFalse);
        expect(summary.rules, isEmpty);
      },
    );

    test('replaceTokens upserts synced tokens without clearing unrelated cache rows', () async {
      final repository = await buildRepository();

      await repository.createToken(baseRequest());
      final listResult = await repository.listTokens();
      final localId = listResult.getOrNull()!.single.id;

      await repository.replaceTokens(const <ClientTokenSummary>[]);
      expect((await repository.listTokens()).getOrNull(), hasLength(1));
      expect((await repository.getTokenById(localId)).isSuccess(), isTrue);

      final now = DateTime.utc(2024, 3);
      await repository.replaceTokens([
        ClientTokenSummary(
          id: 'imported-1',
          clientId: 'remote',
          createdAt: now,
          isRevoked: false,
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: const [],
          version: 2,
          updatedAt: now,
          tokenValue: 'deadbeef',
        ),
      ]);

      final listed = (await repository.listTokens()).getOrNull()!;
      expect(listed.length, 2);
      expect(listed.map((token) => token.id), containsAll([localId, 'imported-1']));

      final importedSecret = await repository.getTokenSecret('imported-1');
      expect(importedSecret.getOrNull()!.tokenValue, equals('deadbeef'));
    });

    test('replaceTokens updates an existing token in place', () async {
      final repository = await buildRepository();
      final now = DateTime.utc(2024, 3);

      await repository.replaceTokens([
        ClientTokenSummary(
          id: 'imported-1',
          clientId: 'remote',
          createdAt: now,
          isRevoked: false,
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: const [],
          tokenValue: 'deadbeef',
        ),
      ]);

      final updatedAt = now.add(const Duration(hours: 1));
      await repository.replaceTokens([
        ClientTokenSummary(
          id: 'imported-1',
          clientId: 'remote-renamed',
          createdAt: now,
          isRevoked: true,
          allTables: true,
          allViews: false,
          allPermissions: false,
          rules: const [],
          version: 3,
          updatedAt: updatedAt,
          tokenValue: 'cafebabe',
        ),
      ]);

      final listed = (await repository.listTokens()).getOrNull()!;
      expect(listed, hasLength(1));
      expect(listed.single.clientId, 'remote-renamed');
      expect(listed.single.isRevoked, isTrue);
      expect(listed.single.version, 3);
      expect(
        (await repository.getTokenSecret('imported-1')).getOrNull()!.tokenValue,
        equals('cafebabe'),
      );
      expect(
        (await repository.getTokenByHash(repository.hashTokenForLookup('deadbeef'))).isError(),
        isTrue,
      );
      expect(
        (await repository.getTokenByHash(repository.hashTokenForLookup('cafebabe'))).isSuccess(),
        isTrue,
      );
    });

    test('replaceTokens preserves token values when secure storage is enabled', () async {
      final secretStore = _FakeTokenSecretStore();
      final repository = await buildRepository(secretStore: secretStore);
      final now = DateTime.utc(2024, 3);

      await repository.replaceTokens([
        ClientTokenSummary(
          id: 'secure-1',
          clientId: 'remote',
          createdAt: now,
          isRevoked: false,
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: const [],
          tokenValue: 'secure-deadbeef',
        ),
      ]);

      final listed = (await repository.listTokens()).getOrNull()!;
      expect(listed.single.tokenValue, isNull);
      expect(
        (await repository.getTokenSecret('secure-1')).getOrNull()!.tokenValue,
        equals('secure-deadbeef'),
      );
      expect(
        secretStore.readSecretSync(repository.hashTokenForLookup('secure-deadbeef')),
        equals('secure-deadbeef'),
      );
    });

    test('listTokens does not hydrate token values or consult secure storage', () async {
      final secretStore = _FakeTokenSecretStore();
      final repository = await buildRepository(secretStore: secretStore);

      await repository.createToken(baseRequest());
      secretStore.resetCounters();

      final listed = (await repository.listTokens()).getOrNull()!;

      expect(listed, hasLength(1));
      expect(listed.single.tokenValue, isNull);
      expect(secretStore.readCallCount, equals(0));
    });

    test('getTokenSecret migrates legacy tokenId secret to tokenHash key', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final dataSource = ClientTokenLocalDataSource(db);
      final repository = ClientTokenRepository(dataSource, secretStore: secretStore);

      const tokenId = 'legacy-1';
      const tokenValue = 'legacy-secret';
      final tokenHash = hashStoredClientToken(tokenValue);
      final now = DateTime.utc(2026, 3, 18);

      await db
          .into(db.clientTokenCacheTable)
          .insert(
            ClientTokenCacheTableCompanion.insert(
              id: tokenId,
              clientId: 'legacy-client',
              name: const Value(''),
              isRevoked: const Value(false),
              createdAt: now,
              updatedAt: Value(now),
              version: const Value(1),
              payloadJson: const Value('{}'),
              allTables: const Value(false),
              allViews: const Value(false),
              allPermissions: const Value(false),
              globalPermissionsJson: Value(jsonEncode(ClientPermissionSet.none.toJson())),
              rulesJson: const Value('[]'),
              syncedAt: now,
              tokenHash: Value(tokenHash),
              tokenValue: const Value('__secure_storage__'),
            ),
          );
      await secretStore.saveSecret(tokenId, tokenValue);

      expect(
        (await repository.getTokenSecret(tokenId)).getOrNull()!.tokenValue,
        equals(tokenValue),
      );
      expect(secretStore.readSecretSync(tokenId), isNull);
      expect(secretStore.readSecretSync(tokenHash), equals(tokenValue));
    });

    test('createToken with unavailable secret store persists plaintext token value', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final dataSource = ClientTokenLocalDataSource(db);
      final repository = ClientTokenRepository(
        dataSource,
        secretStore: NoopTokenSecretStore(),
      );

      final opaque = (await repository.createToken(baseRequest())).getOrNull()!;
      final row = await db.select(db.clientTokenCacheTable).getSingle();

      expect(row.tokenValue, opaque);
      expect(row.tokenValue, isNot('__secure_storage__'));
      final list = (await repository.listTokens()).getOrNull()!;
      expect(
        (await repository.getTokenSecret(list.single.id)).getOrNull()!.tokenValue,
        equals(opaque),
      );
    });

    test('replaceTokens does not update secrets when database transaction fails', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final dataSource = ClientTokenLocalDataSource(db);
      final repository = ClientTokenRepository(dataSource, secretStore: secretStore);
      final now = DateTime.utc(2024, 3);

      await repository.replaceTokens([
        ClientTokenSummary(
          id: 'existing-1',
          clientId: 'remote',
          createdAt: now,
          isRevoked: false,
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: const [],
          tokenValue: 'existing-secret',
        ),
      ]);
      secretStore.resetCounters();

      await db.customStatement('DROP TABLE client_token_cache_table');

      await expectLater(
        repository.replaceTokens([
          ClientTokenSummary(
            id: 'replacement-1',
            clientId: 'remote',
            createdAt: now,
            isRevoked: false,
            allTables: false,
            allViews: true,
            allPermissions: false,
            rules: const [],
            tokenValue: 'replacement-secret',
          ),
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        secretStore.readSecretSync(repository.hashTokenForLookup('existing-secret')),
        equals('existing-secret'),
      );
      expect(
        secretStore.readSecretSync(repository.hashTokenForLookup('replacement-secret')),
        isNull,
      );
    });

    test('createToken cleans up secret when database persistence fails', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final dataSource = ClientTokenLocalDataSource(db);
      final repository = ClientTokenRepository(dataSource, secretStore: secretStore);

      await db.customStatement('DROP TABLE client_token_cache_table');

      expect((await repository.createToken(baseRequest())).isError(), isTrue);
      expect(secretStore.storedKeys, isEmpty);
    });

    test('deleteToken removes row and secret', () async {
      final repository = await buildRepository();
      final opaque = (await repository.createToken(baseRequest())).getOrNull()!;
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      expect((await repository.deleteToken(id)).isSuccess(), isTrue);
      expect((await repository.getTokenById(id)).isError(), isTrue);
      expect(
        (await repository.getTokenByHash(repository.hashTokenForLookup(opaque))).isError(),
        isTrue,
      );
    });

    test('updateToken returns new value and bumps version when policy changes', () async {
      final repository = await buildRepository();
      await repository.createToken(baseRequest());
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      final result = await repository.updateToken(
        id,
        const ClientTokenCreateRequest(
          clientId: 'updated',
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: [],
          payload: {'p': 1},
        ),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.version, 2);
      expect(updateResult.outcome, ClientTokenUpdateOutcome.rotated);
      expect(updateResult.didRotateToken, isTrue);
      expect(updateResult.tokenValue!.length, 64);

      final row = (await repository.getTokenById(id)).getOrNull()!;
      expect(row.clientId, 'updated');
      expect(row.version, 2);
      expect(row.tokenValue, updateResult.tokenValue);
    });

    test('updateToken keeps existing token value and hash when only metadata changes', () async {
      final secretStore = _FakeTokenSecretStore();
      final repository = await buildRepository(secretStore: secretStore);

      final originalTokenValue = (await repository.createToken(baseRequest())).getOrNull()!;
      final originalTokenHash = repository.hashTokenForLookup(originalTokenValue);
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      final result = await repository.updateToken(
        id,
        baseRequest(clientId: 'renamed-client'),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.metadataOnly);
      expect(updateResult.didRotateToken, isFalse);
      expect(updateResult.didChangeMetadata, isTrue);
      expect(updateResult.tokenValue, isNull);
      expect(updateResult.version, 2);

      final stored = (await repository.getTokenById(id)).getOrNull()!;
      expect(stored.clientId, 'renamed-client');
      expect(stored.tokenValue, equals(originalTokenValue));
      expect(stored.version, 2);

      final byHash = (await repository.getTokenByHash(originalTokenHash)).getOrNull()!;
      expect(byHash.id, equals(id));
      expect(secretStore.readSecretSync(originalTokenHash), equals(originalTokenValue));
      expect(secretStore.storedKeys, hasLength(1));
    });

    test('updateToken returns unchanged outcome and skips write when nothing differs', () async {
      final repository = await buildRepository();
      await repository.createToken(baseRequest());
      final id = (await repository.listTokens()).getOrNull()!.single.id;
      final beforeRow = (await repository.getTokenById(id)).getOrNull()!;

      final result = await repository.updateToken(
        id,
        baseRequest(),
        expectedVersion: beforeRow.version,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.unchanged);
      expect(updateResult.didRotateToken, isFalse);
      expect(updateResult.didChangeMetadata, isFalse);
      expect(updateResult.tokenValue, isNull);
      expect(updateResult.version, equals(beforeRow.version));

      final afterRow = (await repository.getTokenById(id)).getOrNull()!;
      expect(afterRow.version, equals(beforeRow.version));
      expect(afterRow.tokenValue, equals(beforeRow.tokenValue));
      expect(afterRow.updatedAt, equals(beforeRow.updatedAt));
    });

    test('updateToken rotates token when only the resource rules differ', () async {
      final repository = await buildRepository();

      await repository.createToken(
        const ClientTokenCreateRequest(
          clientId: 'rule-client',
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: [
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.table,
                name: 'dbo.users',
              ),
              permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
              effect: ClientTokenRuleEffect.allow,
            ),
          ],
        ),
      );
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      final result = await repository.updateToken(
        id,
        const ClientTokenCreateRequest(
          clientId: 'rule-client',
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: [
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.table,
                name: 'dbo.users',
              ),
              permissions: ClientPermissionSet(canRead: true, canUpdate: true, canDelete: false),
              effect: ClientTokenRuleEffect.allow,
            ),
          ],
        ),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.rotated);
      expect(updateResult.tokenValue, isNotNull);
      expect(updateResult.version, 2);
    });

    test('updateToken treats reordered rules as unchanged policy and does not rotate', () async {
      final repository = await buildRepository();

      const ruleA = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
          name: 'dbo.alpha',
        ),
        permissions: ClientPermissionSet(canRead: true, canUpdate: false, canDelete: false),
        effect: ClientTokenRuleEffect.allow,
      );
      const ruleB = ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.view,
          name: 'dbo.beta',
        ),
        permissions: ClientPermissionSet(canRead: true, canUpdate: true, canDelete: false),
        effect: ClientTokenRuleEffect.allow,
      );

      final originalTokenValue = (await repository.createToken(
        const ClientTokenCreateRequest(
          clientId: 'order-client',
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: [ruleA, ruleB],
        ),
      )).getOrNull()!;
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      final result = await repository.updateToken(
        id,
        const ClientTokenCreateRequest(
          clientId: 'order-client',
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: [ruleB, ruleA],
        ),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      final updateResult = result.getOrNull()!;
      expect(updateResult.outcome, ClientTokenUpdateOutcome.unchanged);
      expect(updateResult.tokenValue, isNull);

      final stored = (await repository.getTokenById(id)).getOrNull()!;
      expect(stored.tokenValue, equals(originalTokenValue));
    });

    test('updateToken returns ValidationFailure when expectedVersion mismatches', () async {
      final repository = await buildRepository();
      await repository.createToken(baseRequest());
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      final result = await repository.updateToken(
        id,
        baseRequest(clientId: 'x'),
        expectedVersion: 99,
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });

    test('concurrent rotating updates clean up temporary secret for the losing write', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final dataSource = ClientTokenLocalDataSource(db);
      final repository = ClientTokenRepository(dataSource, secretStore: secretStore);

      await repository.createToken(baseRequest());
      final id = (await repository.listTokens()).getOrNull()!.single.id;

      final releaseConcurrentSaves = Completer<void>();
      final bothUpdatesReachedSave = Completer<void>();
      var concurrentSaveCount = 0;
      secretStore.onSave = (secretKey, tokenValue) async {
        concurrentSaveCount++;
        if (concurrentSaveCount >= 2 && !bothUpdatesReachedSave.isCompleted) {
          bothUpdatesReachedSave.complete();
        }
        if (concurrentSaveCount <= 2) {
          await releaseConcurrentSaves.future;
        }
      };

      Future<Object?> captureResult(Future<Result<ClientTokenUpdateResult>> future) async {
        final result = await future;
        if (result.isSuccess()) {
          return result.getOrNull();
        }
        return result.exceptionOrNull();
      }

      ClientTokenCreateRequest rotatingRequest({required bool ddl}) {
        return ClientTokenCreateRequest(
          clientId: 'concurrent-${ddl ? 'a' : 'b'}',
          allTables: true,
          allViews: false,
          rules: const [],
          payload: const {'k': 'v'},
          agentId: 'agent-1',
          globalPermissions: ClientPermissionSet(
            canRead: true,
            canUpdate: true,
            canDelete: true,
            canDdl: ddl,
          ),
        );
      }

      final updateA = captureResult(
        repository.updateToken(id, rotatingRequest(ddl: true), expectedVersion: 1),
      );
      final updateB = captureResult(
        repository.updateToken(id, rotatingRequest(ddl: false), expectedVersion: 1),
      );

      await bothUpdatesReachedSave.future;
      releaseConcurrentSaves.complete();

      final outcomes = await Future.wait(<Future<Object?>>[updateA, updateB]);
      final successes = outcomes.whereType<ClientTokenUpdateResult>().toList();
      final conflicts = outcomes.whereType<domain.ValidationFailure>().toList();

      expect(successes, hasLength(1));
      expect(conflicts, hasLength(1));

      final winner = successes.single;
      expect(winner.didRotateToken, isTrue);
      final winnerTokenValue = winner.tokenValue!;

      final stored = (await repository.getTokenById(id)).getOrNull()!;
      expect(stored.tokenValue, equals(winnerTokenValue));
      expect(secretStore.storedKeys, hasLength(1));
      expect(
        secretStore.readSecretSync(repository.hashTokenForLookup(winnerTokenValue)),
        equals(winnerTokenValue),
      );
    });
  });
}

class _FakeTokenSecretStore implements ITokenSecretStore {
  final Map<String, String> _secrets = <String, String>{};
  int readCallCount = 0;
  Future<void> Function(String secretKey, String tokenValue)? onSave;

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretKey) async {
    _secrets.remove(secretKey);
  }

  @override
  Future<String?> readSecret(String secretKey) async {
    readCallCount++;
    return _secrets[secretKey];
  }

  String? readSecretSync(String secretKey) => _secrets[secretKey];

  Iterable<String> get storedKeys => _secrets.keys;

  void resetCounters() {
    readCallCount = 0;
  }

  @override
  Future<void> saveSecret(String secretKey, String tokenValue) async {
    final saveHook = onSave;
    if (saveHook != null) {
      await saveHook(secretKey, tokenValue);
    }
    _secrets[secretKey] = tokenValue;
  }
}
