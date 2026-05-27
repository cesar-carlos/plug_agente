import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

void main() {
  group('ClientTokenLocalDataSource', () {
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

    test('createToken returns token and getTokenById round-trips', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      final opaque = await ds.createToken(baseRequest());
      expect(opaque.length, 64);

      final byId = await ds.getTokenById(
        (await ds.listTokens()).single.id,
      );
      expect(byId, isNotNull);
      expect(byId!.clientId, 'alpha');
      expect(byId.tokenValue, opaque);
      expect(byId.agentId, 'agent-1');
      expect(byId.payload, const {'k': 'v'});

      final hash = ds.hashTokenForLookup(opaque);
      final byHash = await ds.getTokenByHash(hash);
      expect(byHash?.id, byId.id);
    });

    test(
      'createToken persists payload.database and canonical global permissions while dropping resource rules in global mode',
      () async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final ds = ClientTokenLocalDataSource(db);

        final opaque = await ds.createToken(
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

        final byId = await ds.getTokenById((await ds.listTokens()).single.id);

        expect(byId, isNotNull);
        expect(byId!.tokenValue, opaque);
        expect(byId.payload, const {'database': 'ERP_MAIN', 'env': 'prod'});
        expect(byId.globalPermissions.canRead, isTrue);
        expect(byId.globalPermissions.canDdl, isTrue);
        expect(byId.globalPermissions.canUpdate, isFalse);
        expect(byId.rules, isEmpty);
      },
    );

    test('listTokens filters by clientIdContains status and sort', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(baseRequest(clientId: 'acme-corp'));
      await Future<void>.delayed(Duration.zero);
      await ds.createToken(baseRequest(clientId: 'beta-inc'));

      final acme = await ds.listTokens(
        query: const ClientTokenListQuery(clientIdContains: 'acme'),
      );
      expect(acme.length, 1);
      expect(acme.single.clientId, 'acme-corp');

      final active = await ds.listTokens(
        query: const ClientTokenListQuery(status: ClientTokenStatusFilter.active),
      );
      expect(active.length, 2);

      final id = active.first.id;
      await ds.markTokenRevoked(id);

      final revokedOnly = await ds.listTokens(
        query: const ClientTokenListQuery(status: ClientTokenStatusFilter.revoked),
      );
      expect(revokedOnly.length, 1);
      expect(revokedOnly.single.id, id);

      final clientAsc = await ds.listTokens(
        query: const ClientTokenListQuery(sort: ClientTokenSortOption.clientAsc),
      );
      expect(clientAsc.map((t) => t.clientId).toList(), ['acme-corp', 'beta-inc']);
    });

    test('listTokens paginates when page and pageSize are set', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(baseRequest(clientId: 't1'));
      await Future<void>.delayed(Duration.zero);
      await ds.createToken(baseRequest(clientId: 't2'));

      final page1 = await ds.listTokens(
        query: const ClientTokenListQuery(
          sort: ClientTokenSortOption.clientAsc,
          page: 1,
          pageSize: 1,
        ),
      );
      expect(page1.length, 1);

      final page2 = await ds.listTokens(
        query: const ClientTokenListQuery(
          sort: ClientTokenSortOption.clientAsc,
          page: 2,
          pageSize: 1,
        ),
      );
      expect(page2.length, 1);
      expect(page1.single.id, isNot(equals(page2.single.id)));
    });

    test('replaceTokens clears and repopulates cache', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(baseRequest());
      expect((await ds.listTokens()).length, 1);

      await ds.replaceTokens(const <ClientTokenSummary>[]);
      expect(await ds.listTokens(), isEmpty);

      final now = DateTime.utc(2024, 3);
      await ds.replaceTokens([
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

      final listed = await ds.listTokens();
      expect(listed.length, 1);
      expect(listed.single.clientId, 'remote');
      expect(listed.single.tokenValue, isNull);
      expect(await ds.getTokenSecret('imported-1'), equals('deadbeef'));
    });

    test('replaceTokens supports multiple imported tokens with unique lookup hashes', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      final now = DateTime.utc(2024, 3);
      await ds.replaceTokens([
        ClientTokenSummary(
          id: 'imported-1',
          clientId: 'remote-a',
          createdAt: now,
          isRevoked: false,
          allTables: false,
          allViews: true,
          allPermissions: false,
          rules: const [],
          tokenValue: 'deadbeef-a',
        ),
        ClientTokenSummary(
          id: 'imported-2',
          clientId: 'remote-b',
          createdAt: now.add(const Duration(minutes: 1)),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: false,
          rules: const [],
          tokenValue: 'deadbeef-b',
        ),
      ]);

      final listed = await ds.listTokens();
      expect(listed, hasLength(2));
      expect(
        await ds.getTokenByHash(ds.hashTokenForLookup('deadbeef-a')),
        isNotNull,
      );
      expect(
        await ds.getTokenByHash(ds.hashTokenForLookup('deadbeef-b')),
        isNotNull,
      );
    });

    test('replaceTokens preserves token values when secure storage is enabled', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final ds = ClientTokenLocalDataSource(db, secretStore: secretStore);

      final now = DateTime.utc(2024, 3);
      await ds.replaceTokens([
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

      final listed = await ds.listTokens();
      expect(listed.single.tokenValue, isNull);
      expect(await ds.getTokenSecret('secure-1'), equals('secure-deadbeef'));
      expect(
        secretStore.readSecretSync(ds.hashTokenForLookup('secure-deadbeef')),
        equals('secure-deadbeef'),
      );
    });

    test('listTokens does not hydrate token values or consult secure storage', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final ds = ClientTokenLocalDataSource(db, secretStore: secretStore);

      await ds.createToken(baseRequest());
      secretStore.resetCounters();

      final listed = await ds.listTokens();

      expect(listed, hasLength(1));
      expect(listed.single.tokenValue, isNull);
      expect(secretStore.readCallCount, equals(0));
    });

    test('getTokenSecret migrates legacy tokenId secret to tokenHash key', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final ds = ClientTokenLocalDataSource(db, secretStore: secretStore);

      const tokenId = 'legacy-1';
      const tokenValue = 'legacy-secret';
      final tokenHash = ds.hashTokenForLookup(tokenValue);
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

      expect(await ds.getTokenSecret(tokenId), equals(tokenValue));
      expect(secretStore.readSecretSync(tokenId), isNull);
      expect(secretStore.readSecretSync(tokenHash), equals(tokenValue));
    });

    test('createToken cleans up secret when database persistence fails', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final ds = ClientTokenLocalDataSource(db, secretStore: secretStore);

      await db.customStatement('DROP TABLE client_token_cache_table');

      await expectLater(ds.createToken(baseRequest()), throwsA(isA<Exception>()));
      expect(secretStore.storedKeys, isEmpty);
    });

    test('deleteToken removes row', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      final token = await ds.createToken(baseRequest());
      final id = (await ds.listTokens()).single.id;
      expect(await ds.deleteToken(id), isTrue);
      expect(await ds.getTokenById(id), isNull);
      expect(await ds.getTokenByHash(ds.hashTokenForLookup(token)), isNull);
    });

    test('updateToken returns new value and bumps version when policy changes', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(baseRequest());
      final id = (await ds.listTokens()).single.id;

      final result = await ds.updateToken(
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
      expect(result, isNotNull);
      expect(result!.version, 2);
      expect(result.outcome, ClientTokenUpdateOutcome.rotated);
      expect(result.didRotateToken, isTrue);
      expect(result.tokenValue!.length, 64);

      final row = await ds.getTokenById(id);
      expect(row!.clientId, 'updated');
      expect(row.version, 2);
      expect(row.tokenValue, result.tokenValue);
    });

    test('updateToken keeps existing token value and hash when only metadata changes', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final ds = ClientTokenLocalDataSource(db, secretStore: secretStore);

      final originalTokenValue = await ds.createToken(baseRequest());
      final originalTokenHash = ds.hashTokenForLookup(originalTokenValue);
      final id = (await ds.listTokens()).single.id;

      final result = await ds.updateToken(
        id,
        baseRequest(clientId: 'renamed-client'),
        expectedVersion: 1,
      );

      expect(result, isNotNull);
      expect(result!.outcome, ClientTokenUpdateOutcome.metadataOnly);
      expect(result.didRotateToken, isFalse);
      expect(result.didChangeMetadata, isTrue);
      expect(result.tokenValue, isNull);
      expect(result.version, 2);

      final stored = await ds.getTokenById(id);
      expect(stored, isNotNull);
      expect(stored!.clientId, 'renamed-client');
      expect(stored.tokenValue, equals(originalTokenValue));
      expect(stored.version, 2);

      final byHash = await ds.getTokenByHash(originalTokenHash);
      expect(byHash, isNotNull);
      expect(byHash!.id, equals(id));
      expect(secretStore.readSecretSync(originalTokenHash), equals(originalTokenValue));
      expect(secretStore.storedKeys, hasLength(1));
    });

    test('updateToken returns unchanged outcome and skips write when nothing differs', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(baseRequest());
      final id = (await ds.listTokens()).single.id;
      final beforeRow = await ds.getTokenById(id);
      expect(beforeRow, isNotNull);

      final result = await ds.updateToken(
        id,
        baseRequest(),
        expectedVersion: beforeRow!.version,
      );

      expect(result, isNotNull);
      expect(result!.outcome, ClientTokenUpdateOutcome.unchanged);
      expect(result.didRotateToken, isFalse);
      expect(result.didChangeMetadata, isFalse);
      expect(result.tokenValue, isNull);
      expect(result.version, equals(beforeRow.version));

      final afterRow = await ds.getTokenById(id);
      expect(afterRow!.version, equals(beforeRow.version));
      expect(afterRow.tokenValue, equals(beforeRow.tokenValue));
      expect(afterRow.updatedAt, equals(beforeRow.updatedAt));
    });

    test('updateToken rotates token when only the resource rules differ', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(
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
      final id = (await ds.listTokens()).single.id;

      final result = await ds.updateToken(
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

      expect(result, isNotNull);
      expect(result!.outcome, ClientTokenUpdateOutcome.rotated);
      expect(result.tokenValue, isNotNull);
      expect(result.version, 2);
    });

    test('updateToken treats reordered rules as unchanged policy and does not rotate', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

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

      final originalTokenValue = await ds.createToken(
        const ClientTokenCreateRequest(
          clientId: 'order-client',
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: [ruleA, ruleB],
        ),
      );
      final id = (await ds.listTokens()).single.id;

      final result = await ds.updateToken(
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

      expect(result, isNotNull);
      expect(result!.outcome, ClientTokenUpdateOutcome.unchanged);
      expect(result.tokenValue, isNull);

      final stored = await ds.getTokenById(id);
      expect(stored!.tokenValue, equals(originalTokenValue));
    });

    test('updateToken throws when expectedVersion mismatches', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await ds.createToken(baseRequest());
      final id = (await ds.listTokens()).single.id;

      await expectLater(
        ds.updateToken(
          id,
          baseRequest(clientId: 'x'),
          expectedVersion: 99,
        ),
        throwsA(isA<ClientTokenVersionConflictException>()),
      );
    });

    test('concurrent rotating updates clean up temporary secret for the losing write', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = _FakeTokenSecretStore();
      final ds = ClientTokenLocalDataSource(db, secretStore: secretStore);

      await ds.createToken(baseRequest());
      final id = (await ds.listTokens()).single.id;

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

      Future<Object?> capture(Future<Object?> future) async {
        try {
          return await future;
        } on Object catch (error) {
          return error;
        }
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

      final updateA = capture(
        ds.updateToken(id, rotatingRequest(ddl: true), expectedVersion: 1),
      );
      final updateB = capture(
        ds.updateToken(id, rotatingRequest(ddl: false), expectedVersion: 1),
      );

      await bothUpdatesReachedSave.future;
      releaseConcurrentSaves.complete();

      final outcomes = await Future.wait(<Future<Object?>>[updateA, updateB]);
      final successes = outcomes.whereType<ClientTokenUpdateResult>().toList();
      final conflicts = outcomes.whereType<ClientTokenVersionConflictException>().toList();

      expect(successes, hasLength(1));
      expect(conflicts, hasLength(1));

      final winner = successes.single;
      expect(winner.didRotateToken, isTrue);
      final winnerTokenValue = winner.tokenValue!;

      final stored = await ds.getTokenById(id);
      expect(stored, isNotNull);
      expect(stored!.tokenValue, equals(winnerTokenValue));
      expect(secretStore.storedKeys, hasLength(1));
      expect(
        secretStore.readSecretSync(ds.hashTokenForLookup(winnerTokenValue)),
        equals(winnerTokenValue),
      );
    });

    test('markTokenRevoked returns false when id missing', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      expect(await ds.markTokenRevoked('no-such-id'), isFalse);
    });
  });
}

class _FakeTokenSecretStore implements ITokenSecretStore {
  final Map<String, String> _secrets = <String, String>{};
  int readCallCount = 0;
  Future<void> Function(String secretKey, String tokenValue)? onSave;

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
