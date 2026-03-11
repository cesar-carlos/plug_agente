import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockExecutePlaygroundQuery extends Mock
    implements ExecutePlaygroundQuery {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockExecuteStreamingQuery extends Mock implements ExecuteStreamingQuery {}

void main() {
  group('PlaygroundProvider', () {
    late MockExecutePlaygroundQuery mockExecutePlaygroundQuery;
    late MockTestDbConnection mockTestDbConnection;
    late MockExecuteStreamingQuery mockExecuteStreamingQuery;
    late PlaygroundProvider provider;

    setUp(() {
      mockExecutePlaygroundQuery = MockExecutePlaygroundQuery();
      mockTestDbConnection = MockTestDbConnection();
      mockExecuteStreamingQuery = MockExecuteStreamingQuery();
      provider = PlaygroundProvider(
        mockExecutePlaygroundQuery,
        mockTestDbConnection,
        mockExecuteStreamingQuery,
      );
    });

    test('should throttle notifyListeners during streaming chunks', () async {
      var listenerCalls = 0;
      provider.addListener(() {
        listenerCalls++;
      });

      when(
        () => mockExecuteStreamingQuery(any(), any(), any()),
      ).thenAnswer((invocation) async {
        final onChunk =
            invocation.positionalArguments[2]
                as void Function(List<Map<String, dynamic>>);
        onChunk([
          {'id': 1},
        ]);
        onChunk([
          {'id': 2},
        ]);
        onChunk([
          {'id': 3},
        ]);
        return const Success(unit);
      });

      await provider.executeQueryWithStreaming(
        'SELECT * FROM users',
        'DSN=Test',
      );

      expect(provider.results.length, 3);
      expect(provider.affectedRows, 3);
      expect(listenerCalls, lessThanOrEqualTo(4));
      expect(listenerCalls, greaterThanOrEqualTo(2));
    });

    test(
      'should expose explicit success state for connection status',
      () async {
        final config = _buildConfig();
        when(() => mockTestDbConnection(any())).thenAnswer((_) async {
          return const Success(true);
        });

        await provider.testConnection(config);

        expect(provider.connectionStatus, AppStrings.queryConnectionSuccess);
        expect(provider.isConnectionStatusSuccess, isTrue);
        expect(provider.error, isNull);
      },
    );
  });
}

Config _buildConfig() {
  final now = DateTime.now();
  return Config(
    id: 'cfg-provider',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: 'DSN=Test',
    username: 'sa',
    databaseName: 'master',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
    agentId: 'agent-1',
  );
}
