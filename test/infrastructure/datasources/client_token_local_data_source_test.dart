import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
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
      expect(listed.single.tokenValue, 'deadbeef');
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

    test('updateToken returns new value and bumps version', () async {
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
      expect(result.tokenValue.length, 64);

      final row = await ds.getTokenById(id);
      expect(row!.clientId, 'updated');
      expect(row.version, 2);
      expect(row.tokenValue, result.tokenValue);
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

    test('markTokenRevoked returns false when id missing', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final ds = ClientTokenLocalDataSource(db);

      expect(await ds.markTokenRevoked('no-such-id'), isFalse);
    });
  });
}
