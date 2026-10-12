import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_verified_query.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../application/services/sql_operation_executor_test.dart' show fixtureConfig;
import 'odbc_sql_operation_transaction_test.dart' show Native, Strings, info;

void main() {
  setUpAll(() => registerFallbackValue(const odbc.ConnectionOptions()));
  late Native native;
  late Strings strings;
  late DirectOdbcConnectionLimiter limiter;
  late OdbcSourceDiscovery sessions;
  late OdbcVerifiedQuery query;
  final metadataSql = OdbcSourceDiscovery.metadataSql('postgres');
  const metadata = odbc.QueryResult(
    columns: ['db', 'cluster_id', 'db_id'],
    rows: [
      ['test_db', 'cluster', '17'],
    ],
    rowCount: 1,
  );
  setUp(() {
    native = Native();
    strings = Strings();
    limiter = DirectOdbcConnectionLimiter(maxConcurrent: 1, acquireTimeout: const Duration(seconds: 1));
    sessions = OdbcSourceDiscovery(native, strings, limiter);
    query = OdbcVerifiedQuery(sessions);
    when(() => strings.resolveConnectionString(fixtureConfig)).thenReturn('DRIVER={fixture};DATABASE=test_db;');
    when(() => native.connect(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Success(
        odbc.Connection(id: 'dedicated', connectionString: '', createdAt: DateTime.utc(2026), isActive: true),
      ),
    );
    when(() => native.disconnect('dedicated')).thenAnswer((_) async => const Success(unit));
    when(() => native.getConnectionDbmsInfo('dedicated')).thenAnswer((_) async => Success(info('postgres')));
    when(
      () => native.executeQueryNamed('dedicated', metadataSql, const {}),
    ).thenAnswer((_) async => const Success(metadata));
    when(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).thenAnswer(
      (_) async => const Success(
        odbc.QueryResult(
          columns: ['id'],
          rows: [
            [7],
          ],
          rowCount: 1,
        ),
      ),
    );
  });
  Future<ExpectedSource> expected() async {
    final proof = await OdbcSourceDiscovery.inspectConnection(native, 'dedicated', fixtureConfig, 'test_db');
    clearInteractions(native);
    return ExpectedSource(dialect: 'postgres', identityHash: proof.identityHash);
  }

  QueryRequest request(ExpectedSource identity) => QueryRequest(
    id: 'read',
    agentId: 'agent',
    query: 'SELECT id FROM fixture',
    timestamp: DateTime.utc(2026),
    sqlHandlingMode: SqlHandlingMode.preserve,
    expectedSource: identity,
  );
  test('both native checks and read use the same connection without reconnect', () async {
    final identity = await expected();
    final result = (await query.execute(
      request(identity),
      fixtureConfig,
      'test_db',
      const Duration(seconds: 1),
    )).getOrThrow();
    expect(result.data, [
      {'id': 7},
    ]);
    verify(() => native.executeQueryNamed('dedicated', metadataSql, const {})).called(2);
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
    final options =
        verify(() => native.connect(any(), options: captureAny(named: 'options'))).captured.single
            as odbc.ConnectionOptions;
    expect(options.autoReconnectOnConnectionLost, isFalse);
    expect(options.replayQueriesAfterReconnect, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(limiter.activeCount, 0);
  });
  test('business SQL errors retain SQL classification instead of identity failure', () async {
    final identity = await expected();
    when(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).thenAnswer(
      (_) async => const Failure(odbc.QueryError(message: 'Syntax error', sqlState: '42000', nativeCode: 156)),
    );
    final result = await query.execute(request(identity), fixtureConfig, 'test_db', const Duration(seconds: 1));
    final failure = result.exceptionOrNull()! as domain.Failure;
    expect(failure, isA<domain.ValidationFailure>());
    expect(failure.context['odbc_sql_state'], '42000');
    expect(failure.context['reason'], 'sql_validation_failed');
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
    verify(() => native.executeQueryNamed('dedicated', metadataSql, const {})).called(1);
  });
  test('change after SELECT discards rows; no second business read', () async {
    final identity = await expected();
    var calls = 0;
    when(() => native.executeQueryNamed('dedicated', metadataSql, const {})).thenAnswer(
      (_) async => Success(
        ++calls == 1
            ? metadata
            : const odbc.QueryResult(
                columns: ['db', 'cluster_id', 'db_id'],
                rows: [
                  ['test_db', 'cluster', '18'],
                ],
                rowCount: 1,
              ),
      ),
    );
    final result = await query.execute(request(identity), fixtureConfig, 'test_db', const Duration(seconds: 1));
    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull().toString(), contains('Executing connection does not match'));
    verify(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any())).called(1);
  });
  test('late metadata cannot dispatch business SQL or release admission while native work is pending', () async {
    final identity = await expected();
    final pending = Completer<Result<odbc.QueryResult>>();
    when(() => native.executeQueryNamed('dedicated', metadataSql, const {})).thenAnswer((_) => pending.future);
    final result = await query.execute(request(identity), fixtureConfig, 'test_db', const Duration(milliseconds: 30));
    expect(result.isError(), isTrue);
    expect(limiter.activeCount, 1);
    verifyNever(() => native.disconnect('dedicated'));
    verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
    pending.complete(const Success(metadata));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    verifyNever(() => native.executeQueryNamed('dedicated', 'SELECT id FROM fixture', any()));
    verify(() => native.disconnect('dedicated')).called(1);
    expect(limiter.activeCount, 0);
  });
}
