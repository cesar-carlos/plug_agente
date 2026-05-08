import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/sql_observer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

void main() {
  late _FakeDatabaseGateway gateway;
  late MockFeatureFlags featureFlags;
  late MockAuthorizeSqlOperation authorizeSqlOperation;
  late SqlObserverService service;
  late List<({String event, Map<String, dynamic> payload})> emitted;

  SqlObserverRegisterCommand command({
    String sql = 'SELECT * FROM users',
    int intervalSeconds = 30,
    bool runImmediately = false,
    String? idempotencyKey,
    SqlObserverCondition condition = SqlObserverCondition.rowsPresent,
    SqlObserverNotificationPolicy notificationPolicy = SqlObserverNotificationPolicy.defaults,
    Duration executionTimeout = ConnectionConstants.sqlObserverDefaultExecutionTimeout,
  }) {
    return SqlObserverRegisterCommand(
      agentId: 'agent-1',
      sql: sql,
      intervalSeconds: intervalSeconds,
      limits: const TransportLimits(maxRows: 50),
      condition: condition,
      notificationPolicy: notificationPolicy,
      executionTimeout: executionTimeout,
      idempotencyKey: idempotencyKey,
      runImmediately: runImmediately,
    );
  }

  setUpAll(() {
    registerFallbackValue(
      QueryRequest(
        id: 'req-1',
        agentId: 'agent-1',
        query: 'SELECT 1',
        timestamp: DateTime.now(),
      ),
    );
  });

  setUp(() {
    gateway = _FakeDatabaseGateway();
    featureFlags = MockFeatureFlags();
    authorizeSqlOperation = MockAuthorizeSqlOperation();
    emitted = <({String event, Map<String, dynamic> payload})>[];
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    service =
        SqlObserverService(
          databaseGateway: gateway,
          normalizerService: QueryNormalizerService(QueryNormalizer()),
          uuid: const Uuid(),
          authorizeSqlOperation: authorizeSqlOperation,
          featureFlags: featureFlags,
        )..setEventEmitter((event, payload) async {
          emitted.add((event: event, payload: payload));
        });
  });

  tearDown(() {
    service.clearSession();
  });

  group('SqlObserverService', () {
    test('should register observer with default metadata', () async {
      final result = await service.register(command());

      expect(result.isSuccess(), isTrue);
      final value = result.getOrThrow();
      expect(value.observerId, isNotEmpty);
      expect(value.intervalSeconds, 30);
      expect(value.condition, SqlObserverCondition.rowsPresent);
      expect(service.activeCount, 1);
    });

    test('should reject interval outside supported range', () async {
      final result = await service.register(
        command(
          intervalSeconds: ConnectionConstants.sqlObserverMinInterval.inSeconds - 1,
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
    });

    test('should reject idempotency key', () async {
      final result = await service.register(
        command(idempotencyKey: 'same-key'),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<domain.ValidationFailure>());
    });

    test('should enforce max observers per session', () async {
      for (var i = 0; i < ConnectionConstants.maxSqlObserversPerSession; i++) {
        final result = await service.register(
          command(sql: 'SELECT $i AS id'),
        );
        expect(result.isSuccess(), isTrue);
      }

      final overflow = await service.register(command(sql: 'SELECT 99 AS id'));

      expect(overflow.isError(), isTrue);
      final failure = overflow.exceptionOrNull();
      expect(failure, isA<domain.ConfigurationFailure>());
    });

    test('should emit notification when immediate execution returns rows', () async {
      gateway.nextResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'ID': 1, 'Name': ' Alice '},
        ],
        timestamp: DateTime.now(),
      );

      final result = await service.register(command(runImmediately: true));
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess(), isTrue);
      expect(emitted, hasLength(1));
      expect(emitted.single.event, 'observer:notification');
      expect(emitted.single.payload['observer_id'], result.getOrThrow().observerId);
      expect(emitted.single.payload['notification_id'], isA<String>());
      expect(emitted.single.payload['row_count'], 1);
      expect(emitted.single.payload['rows'], [
        {'id': 1, 'name': 'Alice'},
      ]);
    });

    test('should not emit when immediate execution returns no rows', () async {
      gateway.nextResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [],
        timestamp: DateTime.now(),
      );

      final result = await service.register(command(runImmediately: true));
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess(), isTrue);
      expect(emitted, isEmpty);
    });

    test('should emit error and keep observer active when execution fails', () async {
      gateway.nextFailure = domain.QueryExecutionFailure.withContext(
        message: 'boom',
        context: const {'operation': 'test'},
      );

      final result = await service.register(command(runImmediately: true));
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess(), isTrue);
      expect(service.activeCount, 1);
      expect(emitted, hasLength(1));
      expect(emitted.single.event, 'observer:error');
      expect(emitted.single.payload['notification_id'], isA<String>());
      expect(emitted.single.payload['consecutive_failures'], 1);
      expect(emitted.single.payload['error'], isA<Map<String, dynamic>>());
    });

    test('should support row_count_gt condition', () async {
      gateway.nextResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'ID': 1},
        ],
        timestamp: DateTime.now(),
      );

      final result = await service.register(
        command(
          runImmediately: true,
          condition: const SqlObserverCondition.rowCountGreaterThan(1),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess(), isTrue);
      expect(emitted, isEmpty);
      final snapshot = service.list().single.toJson();
      expect(snapshot['last_status'], 'condition_not_met');
      expect(snapshot['last_row_count'], 1);
    });

    test('should suppress repeated notifications with once_until_empty policy', () async {
      gateway.nextResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'ID': 1},
        ],
        timestamp: DateTime.now(),
      );

      final registered = await service.register(
        command(
          runImmediately: true,
          notificationPolicy: const SqlObserverNotificationPolicy(
            mode: SqlObserverNotificationMode.onceUntilEmpty,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await service.runOnce(registered.getOrThrow().observerId);

      expect(registered.isSuccess(), isTrue);
      expect(emitted, hasLength(1));
      final snapshot = service.list().single.toJson();
      expect(snapshot['notifications_total'], 1);
      expect(snapshot['last_status'], 'suppressed');
    });

    test('should pass execution timeout to database gateway', () async {
      const timeout = Duration(seconds: 7);
      gateway.nextResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'ID': 1},
        ],
        timestamp: DateTime.now(),
      );

      final result = await service.register(
        command(
          runImmediately: true,
          executionTimeout: timeout,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess(), isTrue);
      expect(gateway.lastTimeout, timeout);
    });

    test('should expose aggregate metrics snapshot', () async {
      gateway.nextResponse = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'ID': 1},
        ],
        timestamp: DateTime.now(),
      );

      await service.register(command(runImmediately: true));
      await Future<void>.delayed(Duration.zero);

      final metrics = service.metricsSnapshot().toJson();
      expect(metrics['active'], 1);
      expect(metrics['registered_total'], 1);
      expect(metrics['ticks_total'], 1);
      expect(metrics['notifications_total'], 1);
    });

    test('should unregister observer and clear session', () async {
      final registered = await service.register(command());
      final observerId = registered.getOrThrow().observerId;

      final unregister = service.unregister(observerId);

      expect(unregister.isSuccess(), isTrue);
      expect(unregister.getOrThrow().cancelled, isTrue);
      expect(service.activeCount, 0);
    });
  });
}

final class _FakeDatabaseGateway implements IDatabaseGateway {
  QueryResponse? nextResponse;
  domain.Failure? nextFailure;
  Duration? lastTimeout;

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
  }) async {
    lastTimeout = timeout;
    final failure = nextFailure;
    if (failure != null) {
      return Failure(failure);
    }
    return Success(
      nextResponse ??
          QueryResponse(
            id: 'exec-1',
            requestId: request.id,
            agentId: request.agentId,
            data: const [],
            timestamp: DateTime.now(),
          ),
    );
  }

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
  }) async {
    return const Success(<SqlCommandResult>[]);
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  }) async {
    return const Success(0);
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    return const Success(true);
  }
}
