import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/application/rpc/sql_operation_rpc_handler.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/sql_operation_executor.dart';
import 'package:plug_agente/application/services/update_maintenance_admission.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/protocol/sql_operation_capability.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/stores/drift_sql_operation_journal.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_database.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/rpc_method_dispatcher_test_support.dart';
import '../rpc/rpc_method_dispatcher_test.dart'
    show
        MockAuthorizeSqlOperation,
        MockDatabaseGateway,
        MockFeatureFlags,
        MockGetClientTokenPolicy,
        MockQueryNormalizerService;

Map<String, dynamic> envelope() => {
  'contractVersion': 1,
  'operationId': '00000000-0000-4000-8000-000000000001',
  'fingerprint': 'b' * 64,
  'sourcePhysicalId': 'c' * 64,
  'database': 'test_db',
  'timeoutMs': 10000,
  'maxAffectedRows': 2,
  'steps': <Map<String, dynamic>>[
    {
      'id': 'insert_parent',
      'effect': 'insert',
      'sql': 'INSERT INTO parent(name) VALUES (:name) RETURNING id',
      'params': {
        'name': {
          'kind': 'value',
          'scalar': {'type': 'string', 'value': "x'); DELETE FROM parent; --"},
        },
      },
      'outputs': {'id': 'integer'},
      'affectedRows': {'min': 1, 'max': 1},
    },
    {
      'id': 'insert_child',
      'effect': 'insert',
      'sql': 'INSERT INTO child(parent_id) VALUES (:parent_id) RETURNING id',
      'params': {
        'parent_id': {'kind': 'step_output', 'stepId': 'insert_parent', 'output': 'id'},
      },
      'outputs': <String, dynamic>{},
      'affectedRows': {'min': 1, 'max': 1},
    },
  ],
};

final fixtureConfig = Config(
  id: 'config',
  driverName: 'PostgreSQL',
  odbcDriverName: 'PostgreSQL',
  connectionString: '',
  username: '',
  databaseName: 'test_db',
  host: 'localhost',
  port: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class Authorizer implements ISqlOperationAuthorizer {
  int calls = 0;
  int? denyAt;
  String revision = 'revision';
  @override
  Future<Result<SqlOperationTarget>> authorize(
    SqlOperationReference ref,
    String token,
    String agent,
    List<SqlOperationStep> steps,
  ) async {
    calls++;
    if (calls == denyAt) return Failure(SqlOperationFailure(code: 'DENIED', message: 'revoked'));
    return Success(
      SqlOperationTarget(
        config: fixtureConfig,
        database: ref.database,
        scopeHash: 'a' * 64,
        authorizationHash: revision,
      ),
    );
  }
}

class Transactions implements ISqlOperationTransactionFactory, ISqlOperationTransaction {
  int opened = 0;
  int commits = 0;
  int rollbacks = 0;
  int closes = 0;
  final executed = <SqlOperationStep>[];
  final bindings = <Map<String, SqlScalar>>[];
  final results = <SqlOperationStepResult>[
    const SqlOperationStepResult(
      rows: [
        {'id': 42},
      ],
      directlyAffectedRows: 1,
    ),
    const SqlOperationStepResult(
      rows: [
        {'id': 43},
      ],
      directlyAffectedRows: 1,
    ),
  ];
  Future<void> Function()? afterStep;
  Future<void> Function()? onCommit;
  bool loseCommit = false;
  bool failRollback = false;
  Exception? executeFailure;
  Result<void>? planValidation;
  @override
  Future<Result<ISqlOperationTransaction>> open(SqlOperationTarget target, Duration timeout) async {
    opened++;
    return Success(this);
  }

  @override
  Result<void> validatePlan(SqlOperationPlan plan) => planValidation ?? const Success(unit);
  @override
  Future<Result<SqlOperationStepResult>> execute(
    SqlOperationStep step,
    Map<String, SqlScalar> parameters,
    Duration timeout,
  ) async {
    executed.add(step);
    bindings.add(parameters);
    await afterStep?.call();
    if (executeFailure != null) return Failure(executeFailure!);
    return Success(results[executed.length - 1]);
  }

  @override
  Future<Result<void>> commit(Duration timeout) async {
    commits++;
    await onCommit?.call();
    return loseCommit
        ? Failure(SqlOperationFailure(code: 'LOST', message: 'commit response lost'))
        : const Success(unit);
  }

  @override
  Future<Result<void>> rollback(Duration timeout) async {
    rollbacks++;
    return failRollback
        ? Failure(SqlOperationFailure(code: 'LOST', message: 'rollback response lost'))
        : const Success(unit);
  }

  @override
  Future<Result<void>> close() async {
    closes++;
    return const Success(unit);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqlOperationJournalDatabase database;
  late DriftSqlOperationJournal journal;
  late Authorizer authorizer;
  late Transactions transactions;
  late SqlOperationExecutor executor;
  late SqlOperationPlan plan;
  setUp(() {
    database = SqlOperationJournalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    journal = DriftSqlOperationJournal(database);
    authorizer = Authorizer();
    transactions = Transactions();
    executor = SqlOperationExecutor(journal: journal, authorizer: authorizer, transactions: transactions);
    plan = const SqlOperationParamsReader().plan(envelope());
  });
  Future<SqlOperationJournalEntry> run() async => (await executor.execute(plan, 'token', 'agent')).getOrThrow();

  test('durable intent precedes SQL; ordered scalar bindings preserve values and one transaction', () async {
    transactions.afterStep = () async {
      expect(
        (await journal.get(plan.operationId, 'a' * 64, plan.fingerprint)).getOrThrow().state,
        SqlOperationJournalState.executing,
      );
    };
    final result = await run();
    expect(result.state, SqlOperationJournalState.completed);
    expect(result.directlyAffectedRows, 2);
    expect(transactions.opened, 1);
    expect(transactions.commits, 1);
    expect(transactions.closes, 1);
    expect(transactions.bindings[1]['parent_id']!.value, '42');
    expect(transactions.bindings[0]['name']!.value, contains('DELETE'));
    expect(authorizer.calls, 4);
    expect((await run()).executionId, result.executionId);
    expect(transactions.executed.length, 2);
  });
  test('concurrent duplicate calls dispatch once', () async {
    final completed = await Future.wait([run(), run()]);
    expect(completed.map((r) => r.executionId).toSet().length, 1);
    expect(transactions.opened, 1);
  });
  test('same supplied fingerprint with changed SQL is refused by local content hash', () async {
    await run();
    final changed = envelope();
    (changed['steps'] as List<Map<String, dynamic>>).first['sql'] =
        'INSERT INTO other_table(name) VALUES (:name) RETURNING id';
    final result = await executor.execute(const SqlOperationParamsReader().plan(changed), 'token', 'agent');
    expect(result.isError(), isTrue);
    expect(transactions.opened, 1);
  });
  for (final count in <int?>[null, -1, 2]) {
    test('unreliable or excessive row count $count causes confirmed rollback', () async {
      transactions.results[0] = SqlOperationStepResult(
        rows: const [
          {'id': 42},
        ],
        directlyAffectedRows: count,
      );
      final result = await run();
      expect(result.state, SqlOperationJournalState.rolledBack);
      expect(result.directlyAffectedRows, isNull);
      expect(transactions.commits, 0);
      expect(transactions.rollbacks, 1);
    });
  }
  test('failed read condition rolls back and suppresses subsequent writes', () async {
    final raw = envelope();
    (raw['steps'] as List<Map<String, dynamic>>).first['expectedRows'] = {'min': 0, 'max': 0};
    plan = const SqlOperationParamsReader().plan(raw);
    expect((await run()).state, SqlOperationJournalState.rolledBack);
    expect(transactions.executed.length, 1);
  });
  test('native capability refusal is checked before any business SQL', () async {
    transactions.planValidation = Failure(SqlOperationFailure(code: 'UNAVAILABLE', message: 'unsupported'));
    expect((await run()).state, SqlOperationJournalState.rolledBack);
    expect(transactions.executed, isEmpty);
  });
  test('initial denial has no journal claim or connection', () async {
    authorizer.denyAt = 1;
    expect((await executor.execute(plan, 'token', 'agent')).isError(), isTrue);
    expect(transactions.opened, 0);
    expect((await journal.get(plan.operationId, 'a' * 64, plan.fingerprint)).isError(), isTrue);
  });
  test('revocation immediately before commit causes rollback', () async {
    authorizer.denyAt = 4;
    expect((await run()).state, SqlOperationJournalState.rolledBack);
    expect(transactions.commits, 0);
  });
  test('changed live source or policy during SQL prevents commit', () async {
    transactions.afterStep = () async {
      authorizer.revision = 'changed';
    };
    expect((await run()).state, SqlOperationJournalState.rolledBack);
    expect(transactions.executed.length, 1);
  });
  test('accepted cancellation rolls back between steps, never claims reversal early', () async {
    transactions.afterStep = () async {
      final receipt = (await executor.cancel(plan, 'token', 'agent')).getOrThrow();
      expect(receipt.state, SqlOperationJournalState.cancellationRequested);
    };
    expect((await run()).state, SqlOperationJournalState.rolledBack);
    expect(transactions.executed.length, 1);
  });
  test('cancellation after commit begins may still complete', () async {
    transactions.onCommit = () async {
      await executor.cancel(plan, 'token', 'agent');
    };
    expect((await run()).state, SqlOperationJournalState.completed);
  });
  test('lost commit response remains unknown and duplicate does not retry', () async {
    transactions.loseCommit = true;
    expect((await run()).state, SqlOperationJournalState.outcomeUnknown);
    expect((await run()).state, SqlOperationJournalState.outcomeUnknown);
    expect(transactions.commits, 1);
    expect(transactions.rollbacks, 0);
  });
  test('rollback failure remains unknown', () async {
    transactions.results[0] = const SqlOperationStepResult(rows: [], directlyAffectedRows: null);
    transactions.failRollback = true;
    expect((await run()).state, SqlOperationJournalState.outcomeUnknown);
  });
  test('native timeout never overlaps a rollback and cannot be reexecuted', () async {
    transactions.executeFailure = TimeoutException('native call in progress');
    expect((await run()).state, SqlOperationJournalState.outcomeUnknown);
    await run();
    expect(transactions.executed.length, 1);
    expect(transactions.rollbacks, 0);
  });
  test('binary floating point scalar output is not silently treated as exact decimal', () async {
    final raw = envelope();
    (raw['steps'] as List<Map<String, dynamic>>).first['outputs'] = {'id': 'decimal'};
    plan = const SqlOperationParamsReader().plan(raw);
    transactions.results[0] = const SqlOperationStepResult(
      rows: [
        {'id': 0.1},
      ],
      directlyAffectedRows: 1,
    );
    expect((await run()).state, SqlOperationJournalState.rolledBack);
  });
  test('dispatcher adds durable operation handlers without replacing existing methods', () async {
    final gateway = MockDatabaseGateway();
    final dispatcher = RpcMethodDispatcher(
      streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
      databaseGateway: gateway,
      healthService: HealthService(metricsCollector: MetricsCollector(), gateway: gateway),
      normalizerService: MockQueryNormalizerService(),
      uuid: const Uuid(),
      authorizeSqlOperation: MockAuthorizeSqlOperation(),
      getClientTokenPolicy: MockGetClientTokenPolicy(),
      getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
      featureFlags: MockFeatureFlags(),
      loadOpenRpcDocument: () async => {
        'methods': ['existing'],
      },
      additionalHandlers: [
        for (final method in ['sql.operation.execute', 'sql.operation.get', 'sql.operation.cancel'])
          SqlOperationRpcHandler(method, executor, enabled: () => true),
      ],
    );
    final result = await dispatcher.dispatch(
      RpcRequest(jsonrpc: '2.0', id: 'dispatch', method: 'sql.operation.execute', params: envelope()),
      'agent',
      clientToken: 'token',
      negotiatedExtensions: {SqlOperationCapability.key: SqlOperationCapability.advertisement},
    );
    expect(result.error, isNull);
    expect(transactions.commits, 1);
    final discovery = await dispatcher.dispatch(
      const RpcRequest(jsonrpc: '2.0', id: 'discover', method: 'rpc.discover'),
      'agent',
    );
    expect(discovery.error, isNull);
    final denied = await dispatcher.dispatch(
      RpcRequest(jsonrpc: '2.0', id: 'unauthenticated', method: 'sql.operation.execute', params: envelope()),
      'agent',
    );
    expect(denied.error, isNotNull);
    expect(transactions.opened, 1);
  });
  test('RPC requires live opt-in and negotiated capability before opening a transaction', () async {
    var enabled = false;
    final handler = SqlOperationRpcHandler('sql.operation.execute', executor, enabled: () => enabled);
    Future<RpcResponse> request(Map<String, dynamic> extensions) => handler.handle(
      RpcRequest(jsonrpc: '2.0', id: 'gate', method: handler.method, params: envelope()),
      RpcDispatchContext(
        agentId: 'agent',
        clientToken: 'token',
        streamEmitter: null,
        limits: const TransportLimits(),
        negotiatedExtensions: extensions,
      ),
    );
    String? code(RpcResponse response) => (response.error?.data as Map<String, dynamic>?)?['failure_code'] as String?;
    final capability = <String, dynamic>{SqlOperationCapability.key: SqlOperationCapability.advertisement};
    expect(code(await request(capability)), 'CAPABILITY_UNAVAILABLE');
    enabled = true;
    for (final raw in <Object?>[
      null,
      true,
      <String, dynamic>{},
      {...SqlOperationCapability.advertisement, 'version': 2},
    ]) {
      expect(code(await request({SqlOperationCapability.key: raw})), 'CAPABILITY_UNAVAILABLE');
    }
    expect(
      code(
        await request({
          SqlOperationCapability.key: {...SqlOperationCapability.advertisement, 'maxSteps': 1},
        }),
      ),
      'SQL_OPERATION_NEGOTIATED_LIMIT',
    );
    expect(transactions.opened, 0);
    expect((await request(capability)).error, isNull);
    enabled = false;
    expect(code(await request(capability)), 'CAPABILITY_UNAVAILABLE');
    expect(transactions.opened, 1);
  });
  test('maintenance drains admitted operations and refuses new claims until recovery', () async {
    final maintenance = UpdateMaintenanceAdmission();
    addTearDown(maintenance.dispose);
    executor = SqlOperationExecutor(
      journal: journal,
      authorizer: authorizer,
      transactions: transactions,
      maintenanceGate: maintenance,
    );
    transactions.afterStep = () async {
      expect(maintenance.idle, isFalse);
      maintenance.transition('update', UpdateMaintenancePhase.draining);
    };
    expect((await run()).state, SqlOperationJournalState.completed);
    expect(maintenance.idle, isTrue);
    expect((await executor.execute(plan, 'token', 'agent')).isError(), isTrue);
    expect(transactions.opened, 1);
  });
  test('RPC execute and status use the durable receipt, cancellation is not a second execution', () async {
    const context = RpcDispatchContext(
      negotiatedExtensions: {SqlOperationCapability.key: SqlOperationCapability.advertisement},
      streamEmitter: null,
      agentId: 'agent',
      clientToken: 'token',
      limits: TransportLimits(),
    );
    final execute = SqlOperationRpcHandler('sql.operation.execute', executor, enabled: () => true);
    final response = await execute.handle(
      RpcRequest(jsonrpc: '2.0', id: 'rpc1', method: execute.method, params: envelope()),
      context,
    );
    expect(response.error, isNull);
    final ref = envelope()
      ..remove('steps')
      ..remove('timeoutMs')
      ..remove('maxAffectedRows');
    final status = await SqlOperationRpcHandler(
      'sql.operation.get',
      executor,
      enabled: () => true,
    ).handle(RpcRequest(jsonrpc: '2.0', id: 'rpc2', method: 'sql.operation.get', params: ref), context);
    expect(status.result, response.result);
    final mismatched = envelope()..['client_token'] = 'another-token';
    expect(
      (await execute.handle(
        RpcRequest(jsonrpc: '2.0', id: 'rpc3', method: execute.method, params: mismatched),
        context,
      )).error,
      isNotNull,
    );
    expect(transactions.opened, 1);
  });
}
