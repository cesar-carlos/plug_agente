import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:uuid/uuid.dart';

// Explicit private three-engine fixture only. Never loads .env or registered sources.
void main() {
  final path = Platform.environment['PERSONA_SQL_FIXTURE_MANIFEST'];
  if (path == null) throw StateError('PERSONA_SQL_FIXTURE_MANIFEST is required.');
  final manifest = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final runId = manifest['runId'] as String;
  final root = Directory(manifest['root'] as String).resolveSymbolicLinksSync();
  if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(runId) ||
      !root.endsWith('${Platform.pathSeparator}$runId')) {
    throw StateError('Only a newly provisioned private fixture is accepted.');
  }
  final engines = manifest['engines'] as Map<String, dynamic>;
  late odbc.ServiceLocator locator;
  late odbc.OdbcService service;
  setUpAll(() async {
    locator = odbc.ServiceLocator()..initialize(useAsync: true, asyncWorkerCount: 2);
    service = locator.asyncService;
    (await service.initialize()).getOrThrow();
  });
  tearDownAll(() => locator.shutdown());

  for (final engine in ['postgres', 'mssql', 'sybase']) {
    final fixture = engines[engine] as Map<String, dynamic>?;
    if (fixture == null) throw StateError('Missing mandatory engine: $engine');
    final database = fixture['database'] as String;
    if (database != runId) {
      throw StateError('Private fixture database mismatch: $engine');
    }
    test(
      '$engine: restricted principal proves identity without business access, then loses SELECT on revocation',
      () async {
        final adminConfig = Config(
          id: runId,
          driverName: engine,
          odbcDriverName: engine,
          connectionString: fixture['connectionString'] as String,
          username: '',
          databaseName: database,
          host: '127.0.0.1',
          port: fixture['port'] as int,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final admin = (await service.connect(adminConfig.connectionString)).getOrThrow().id;
        String? reader;
        Future<void> provision(String sql) async {
          final result = await service.executeQuery(sql, connectionId: admin);
          expect(result.isSuccess(), isTrue, reason: '$engine: private permission fixture provisioning failed');
        }

        try {
          // Identity is proven before creating any principal or object in the private fixture.
          final enrolled = await OdbcSourceDiscovery.inspectConnection(service, admin, adminConfig, database);
          expect(enrolled.dialect, engine);
          final password = 'Fixture_${const Uuid().v4().replaceAll('-', '')}!';
          const user = 'se7e_identity_reader';
          final table = switch (engine) {
            'postgres' => 'public.identity_permission_fixture',
            'mssql' => 'dbo.identity_permission_fixture',
            'sybase' => 'DBA.identity_permission_fixture',
            _ => 'identity_permission_fixture',
          };
          await provision('CREATE TABLE $table (id INTEGER NOT NULL PRIMARY KEY)');
          await provision('INSERT INTO $table (id) VALUES (7)');
          switch (engine) {
            case 'postgres':
              await provision("CREATE ROLE $user LOGIN PASSWORD '$password' NOSUPERUSER NOCREATEDB NOCREATEROLE");
              await provision('GRANT CONNECT ON DATABASE "$runId" TO $user');
              await provision('GRANT USAGE ON SCHEMA public TO $user');
              await provision('GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_system() TO $user');
            case 'mssql':
              await provision("CREATE LOGIN $user WITH PASSWORD = '$password', CHECK_POLICY = OFF");
              await provision('CREATE USER $user FOR LOGIN $user');
            case 'sybase':
              await provision('CREATE USER $user IDENTIFIED BY "$password"');
              await provision('GRANT SELECT ON DBA.se7e_source_identity TO $user');
          }
          String credential(String connection, String key, String value) {
            final pattern = RegExp('(^|;)$key=[^;]*', caseSensitive: false);
            if (pattern.allMatches(connection).length != 1) {
              throw StateError('Explicit unique fixture credential field required: $key');
            }
            return connection.replaceFirstMapped(pattern, (match) => '${match[1]}$key=$value');
          }

          final connection = credential(credential(adminConfig.connectionString, 'UID', user), 'PWD', password);
          final config = adminConfig.copyWith(connectionString: connection);
          reader = (await service.connect(connection)).getOrThrow().id;
          final whoSql = switch (engine) {
            'sybase' => 'SELECT CURRENT USER',
            _ => 'SELECT CURRENT_USER',
          };
          final who = (await service.executeQuery(whoSql, connectionId: reader)).getOrThrow();
          expect(who.rows.single.single.toString().trim().toLowerCase(), user);
          final proof = await OdbcSourceDiscovery.inspectConnection(service, reader, config, database);
          expect(proof.identityHash, enrolled.identityHash);
          expect((await service.executeQuery('SELECT id FROM $table', connectionId: reader)).isError(), isTrue);

          await provision('GRANT SELECT ON $table TO $user');
          // New attachment ensures each engine observes the new grant consistently.
          (await service.disconnect(reader)).getOrThrow();
          reader = (await service.connect(connection)).getOrThrow().id;
          final rows = (await service.executeQuery('SELECT id FROM $table', connectionId: reader)).getOrThrow();
          expect(rows.rows, [
            [7],
          ]);
          for (final sql in [
            'INSERT INTO $table (id) VALUES (8)',
            'UPDATE $table SET id=9 WHERE id=7',
            'DELETE FROM $table WHERE id=7',
            'ALTER TABLE $table ADD forbidden INTEGER',
            'DROP TABLE $table',
          ]) {
            expect(
              (await service.executeQuery(sql, connectionId: reader)).isError(),
              isTrue,
              reason: '$engine: SELECT-only principal must not mutate the private fixture',
            );
          }
          await provision('REVOKE SELECT ON $table FROM $user');
          (await service.disconnect(reader)).getOrThrow();
          reader = (await service.connect(connection)).getOrThrow().id;
          expect((await service.executeQuery('SELECT id FROM $table', connectionId: reader)).isError(), isTrue);
          final after = await OdbcSourceDiscovery.inspectConnection(service, reader, config, database);
          expect(after.identityHash, enrolled.identityHash);
          final unchanged = (await service.executeQuery('SELECT id FROM $table', connectionId: admin)).getOrThrow();
          expect(unchanged.rows, [
            [7],
          ]);
        } finally {
          if (reader != null) (await service.disconnect(reader)).getOrThrow();
          (await service.disconnect(admin)).getOrThrow();
        }
      },
    );
  }
}
