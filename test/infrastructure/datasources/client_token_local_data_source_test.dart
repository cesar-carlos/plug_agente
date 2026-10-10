import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show ApplyInterceptor, Value;
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

import '../../helpers/token_page_query_recorder.dart';

class _PausedTokenDataSource extends ClientTokenLocalDataSource {
  _PausedTokenDataSource(super._database);

  final snapshotReady = Completer<void>();
  final releaseSnapshot = Completer<void>();
  bool pauseNextRead = true;

  @override
  Future<ClientTokenCacheData?> findRowById(String tokenId) async {
    final row = await super.findRowById(tokenId);
    if (pauseNextRead) {
      pauseNextRead = false;
      snapshotReady.complete();
      await releaseSnapshot.future;
    }
    return row;
  }
}

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

    for (final sort in ClientTokenSortOption.values) {
      for (final status in ClientTokenStatusFilter.values) {
        test('$sort $status pages use indexes and preserve the ID tie-break without sorting', () async {
          final recorder = TokenPageQueryRecorder();
          final db = AppDatabase(executor: NativeDatabase.memory().interceptWith(recorder));
          addTearDown(db.close);
          final source = ClientTokenLocalDataSource(db);
          await db.batch(
            (batch) => batch.insertAll(
              db.clientTokenCacheTable,
              List.generate(
                102,
                (index) => ClientTokenCacheTableCompanion.insert(
                  id: 'id-${index.toString().padLeft(3, '0')}',
                  clientId: index < 51 ? 'Alpha' : 'alpha',
                  tokenHash: Value('hash-$index'),
                  createdAt: DateTime.utc(2026, 1, index < 51 ? 1 : 2),
                  syncedAt: DateTime.utc(2026),
                  isRevoked: Value(index.isOdd),
                ),
              ),
            ),
          );
          final query = ClientTokenListQuery(sort: sort, status: status, page: 2, pageSize: 25);
          final page = await source.listTokenPage(query: query);
          final plans = await recorder.explainPageQuery(db.executor);
          expect(plans.join(' '), contains('USING INDEX idx_client_token_'));
          expect(plans.join(' '), isNot(contains('TEMP B-TREE')));
          final all = await source.listTokens(
            query: ClientTokenListQuery(sort: sort, status: status),
          );
          expect(page.items.map((item) => item.id), all.skip(25).take(25).map((item) => item.id));
          expect(page.totalCount, all.length);
          for (var index = 1; index < all.length; index++) {
            final previous = all[index - 1];
            final current = all[index];
            final dateComparison = previous.createdAt.compareTo(current.createdAt);
            expect(sort == ClientTokenSortOption.oldest ? dateComparison <= 0 : dateComparison >= 0, isTrue);
            if (dateComparison == 0) expect(previous.id.compareTo(current.id), lessThan(0));
          }
        });
      }
    }

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

    test('repeated revocation preserves the confirmed version and timestamp', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);
      await insertSummary(ds, summary: baseSummary());
      expect(await ds.markTokenRevoked('token-1'), isTrue);
      final revoked = (await ds.findRowById('token-1'))!;
      expect(await ds.markTokenRevoked('token-1'), isTrue);
      final repeated = (await ds.findRowById('token-1'))!;
      expect(repeated.version, revoked.version);
      expect(repeated.updatedAt, revoked.updatedAt);
    });

    for (final action in ['delete', 'revoke']) {
      test('$action holds the SQLite transaction across the row snapshot and write', () async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final ds = _PausedTokenDataSource(db);
        await insertSummary(ds, summary: baseSummary());
        final mutation = action == 'delete' ? ds.deleteToken('token-1') : ds.markTokenRevoked('token-1');
        await ds.snapshotReady.future;
        final competingUpdate = ds.applyTokenUpdate(
          tokenId: 'token-1',
          expectedVersion: 1,
          companion: const ClientTokenCacheTableCompanion(
            tokenHash: Value('rotated-hash'),
            version: Value(2),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        ds.releaseSnapshot.complete();
        final result = await mutation;
        expect(await competingUpdate, 0);
        if (action == 'delete') {
          expect((result! as ClientTokenCacheData).tokenHash, 'hash-1');
          expect(await ds.findRowById('token-1'), isNull);
        } else {
          expect(result, isTrue);
          expect((await ds.findRowById('token-1'))!.isRevoked, isTrue);
        }
      });
    }

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
        expectedTokenHash: 'hash-1',
        expectedVersion: 1,
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
