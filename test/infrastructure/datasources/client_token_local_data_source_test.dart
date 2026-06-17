import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

void main() {
  group('ClientTokenLocalDataSource', () {
    ClientTokenSummary baseSummary({
      String id = 'token-1',
      String clientId = 'alpha',
      DateTime? createdAt,
    }) {
      final now = createdAt ?? DateTime.utc(2026, 3, 18);
      return ClientTokenSummary(
        id: id,
        clientId: clientId,
        createdAt: now,
        isRevoked: false,
        allTables: true,
        allViews: false,
        allPermissions: true,
        globalPermissions: ClientPermissionSet.fullAccess,
        rules: const [],
        payload: const {'k': 'v'},
        agentId: 'agent-1',
      );
    }

    Future<void> insertSummary(
      ClientTokenLocalDataSource ds, {
      required ClientTokenSummary summary,
      String tokenHash = 'hash-1',
      String? persistedTokenValue = 'opaque-value',
    }) {
      return ds.insertToken(
        summary: summary,
        tokenHash: tokenHash,
        persistedTokenValue: persistedTokenValue,
        syncedAt: summary.createdAt,
      );
    }

    test('insertToken and findRowById round-trip persisted columns', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(ds, summary: baseSummary());

      final row = await ds.findRowById('token-1');
      expect(row, isNotNull);
      expect(row!.clientId, 'alpha');
      expect(row.tokenValue, 'opaque-value');
      expect(row.tokenHash, 'hash-1');
      expect(row.agentId, 'agent-1');
    });

    test('mapRowToSummaryWithoutTokenValue decodes payload and permissions', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(
        ds,
        summary: ClientTokenSummary(
          id: 'global-1',
          clientId: 'global-client',
          createdAt: DateTime.utc(2026, 3, 18),
          isRevoked: false,
          allTables: true,
          allViews: false,
          allPermissions: false,
          globalPermissions: const ClientPermissionSet(
            canRead: true,
            canUpdate: false,
            canDelete: false,
            canDdl: true,
          ),
          rules: const [
            ClientTokenRule(
              resource: DatabaseResource(
                resourceType: DatabaseResourceType.table,
                name: 'dbo.should_be_persisted',
              ),
              permissions: ClientPermissionSet(
                canRead: true,
                canUpdate: true,
                canDelete: false,
              ),
              effect: ClientTokenRuleEffect.allow,
            ),
          ],
          payload: const {'database': 'ERP_MAIN', 'env': 'prod'},
        ),
      );

      final summary = ds.mapRowToSummaryWithoutTokenValue(
        (await ds.findRowById('global-1'))!,
      );

      expect(summary.tokenValue, isNull);
      expect(summary.payload, const {'database': 'ERP_MAIN', 'env': 'prod'});
      expect(summary.globalPermissions.canRead, isTrue);
      expect(summary.globalPermissions.canDdl, isTrue);
      expect(summary.rules, hasLength(1));
    });

    test('listTokens filters by clientIdContains status and sort', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(
        ds,
        summary: baseSummary(id: 't1', clientId: 'acme-corp'),
      );
      await insertSummary(
        ds,
        summary: baseSummary(
          id: 't2',
          clientId: 'beta-inc',
          createdAt: DateTime.utc(2026, 3, 19),
        ),
        tokenHash: 'hash-2',
      );

      final acme = await ds.listTokens(
        query: const ClientTokenListQuery(clientIdContains: 'acme'),
      );
      expect(acme.length, 1);
      expect(acme.single.clientId, 'acme-corp');

      final active = await ds.listTokens(
        query: const ClientTokenListQuery(status: ClientTokenStatusFilter.active),
      );
      expect(active.length, 2);

      await ds.markTokenRevoked('t1');

      final revokedOnly = await ds.listTokens(
        query: const ClientTokenListQuery(status: ClientTokenStatusFilter.revoked),
      );
      expect(revokedOnly.length, 1);
      expect(revokedOnly.single.id, 't1');

      final clientAsc = await ds.listTokens(
        query: const ClientTokenListQuery(sort: ClientTokenSortOption.clientAsc),
      );
      expect(clientAsc.map((t) => t.clientId).toList(), ['acme-corp', 'beta-inc']);
    });

    test('listTokens paginates when page and pageSize are set', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(
        ds,
        summary: baseSummary(id: 't1', clientId: 't1-client'),
      );
      await insertSummary(
        ds,
        summary: baseSummary(
          id: 't2',
          clientId: 't2-client',
          createdAt: DateTime.utc(2026, 3, 19),
        ),
        tokenHash: 'hash-2',
      );

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

    test('replaceTokenRows upserts without clearing unrelated cache rows', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(ds, summary: baseSummary());
      expect((await ds.listTokens()).length, 1);

      final now = DateTime.utc(2024, 3);
      await ds.replaceTokenRows(
        rows: [
          (
            summary: ClientTokenSummary(
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
            ),
            tokenHash: hashStoredClientToken('deadbeef'),
            persistedTokenValue: 'deadbeef',
          ),
        ],
      );

      final listed = await ds.listTokens();
      expect(listed.length, 2);
      expect(listed.map((token) => token.id), containsAll(['token-1', 'imported-1']));
    });

    test('deleteToken returns deleted row when present', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(ds, summary: baseSummary());
      final deleted = await ds.deleteToken('token-1');
      expect(deleted, isNotNull);
      expect(deleted!.id, 'token-1');
      expect(await ds.findRowById('token-1'), isNull);
    });

    test('markTokenRevoked returns false when id missing', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      expect(await ds.markTokenRevoked('no-such-id'), isFalse);
    });

    test('updatePersistedTokenValue updates only token_value column', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      await insertSummary(ds, summary: baseSummary());
      await ds.updatePersistedTokenValue(
        tokenId: 'token-1',
        tokenValue: '__secure_storage__',
      );

      final row = await ds.findRowById('token-1');
      expect(row!.tokenValue, '__secure_storage__');
    });

    test('findRowByHash locates persisted hash', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);
      const tokenHash = 'abc123';

      await db
          .into(db.clientTokenCacheTable)
          .insert(
            ClientTokenCacheTableCompanion.insert(
              id: 'hash-target',
              clientId: 'client',
              name: const Value(''),
              isRevoked: const Value(false),
              createdAt: DateTime.utc(2026, 3, 18),
              updatedAt: const Value(null),
              version: const Value(1),
              payloadJson: const Value('{}'),
              allTables: const Value(false),
              allViews: const Value(false),
              allPermissions: const Value(false),
              globalPermissionsJson: Value(jsonEncode(ClientPermissionSet.none.toJson())),
              rulesJson: const Value('[]'),
              syncedAt: DateTime.utc(2026, 3, 18),
              tokenHash: const Value(tokenHash),
              tokenValue: const Value(null),
            ),
          );

      expect((await ds.findRowByHash(tokenHash))?.id, 'hash-target');
    });
  });
}
