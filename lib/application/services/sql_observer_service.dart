import 'dart:async';

import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart' show sqlStatementsForClientTokenAuthorization;
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

typedef SqlObserverEventEmitter =
    Future<void> Function(
      String event,
      Map<String, dynamic> payload,
    );

final class SqlObserverService {
  SqlObserverService({
    required IDatabaseGateway databaseGateway,
    required QueryNormalizerService normalizerService,
    required Uuid uuid,
    required AuthorizeSqlOperation authorizeSqlOperation,
    required FeatureFlags featureFlags,
    DateTime Function()? now,
  }) : _databaseGateway = databaseGateway,
       _normalizerService = normalizerService,
       _uuid = uuid,
       _authorizeSqlOperation = authorizeSqlOperation,
       _featureFlags = featureFlags,
       _now = now ?? DateTime.now;

  final IDatabaseGateway _databaseGateway;
  final QueryNormalizerService _normalizerService;
  final Uuid _uuid;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final FeatureFlags _featureFlags;
  final DateTime Function() _now;

  final Map<String, _SqlObserverRegistration> _observers = {};
  SqlObserverEventEmitter? _emitEvent;

  void setEventEmitter(SqlObserverEventEmitter? emitEvent) {
    _emitEvent = emitEvent;
  }

  int get activeCount => _observers.length;

  Future<Result<SqlObserverRegisterResult>> register(
    SqlObserverRegisterCommand command,
  ) async {
    if (_observers.length >= ConnectionConstants.maxSqlObserversPerSession) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Maximum SQL observers per session reached',
          context: {
            'reason': 'observer_capacity_exceeded',
            'max_observers': ConnectionConstants.maxSqlObserversPerSession,
          },
        ),
      );
    }

    final validation = _validateCommand(command);
    if (validation.isError()) {
      return Failure(validation.exceptionOrNull()! as domain.Failure);
    }

    final authorization = await _authorizeCommand(command);
    if (authorization.isError()) {
      return Failure(authorization.exceptionOrNull()! as domain.Failure);
    }

    final observerId = _uuid.v4();
    final createdAt = _now();
    final interval = Duration(seconds: command.intervalSeconds);
    final nextRunAt = command.runImmediately ? createdAt : createdAt.add(interval);
    final observer = _SqlObserverRegistration(
      observerId: observerId,
      agentId: command.agentId,
      sql: command.sql,
      parameters: command.parameters,
      database: command.database,
      clientToken: command.clientToken,
      interval: interval,
      maxRows: command.limits.maxRows,
      sqlHandlingMode: command.sqlHandlingMode,
      expectMultipleResults: command.expectMultipleResults,
      createdAt: createdAt,
      nextRunAt: nextRunAt,
      emitEvent: _emitObserverEvent,
      execute: _executeObserver,
      now: _now,
    );

    _observers[observerId] = observer;
    observer.start(runImmediately: command.runImmediately);

    return Success(
      SqlObserverRegisterResult(
        observerId: observerId,
        intervalSeconds: command.intervalSeconds,
        condition: SqlObserverCondition.rowsPresent,
        createdAt: createdAt,
        nextRunAt: nextRunAt,
      ),
    );
  }

  Result<SqlObserverUnregisterResult> unregister(String observerId) {
    final observer = _observers.remove(observerId);
    if (observer == null) {
      return Success(
        SqlObserverUnregisterResult(
          observerId: observerId,
          cancelled: false,
        ),
      );
    }
    observer.cancel();
    return Success(
      SqlObserverUnregisterResult(
        observerId: observerId,
        cancelled: true,
      ),
    );
  }

  List<SqlObserverSnapshot> list() {
    return _observers.values.map((observer) => observer.snapshot()).toList(growable: false);
  }

  void clearSession() {
    for (final observer in _observers.values) {
      observer.cancel();
    }
    _observers.clear();
  }

  Result<void> _validateCommand(SqlObserverRegisterCommand command) {
    if (command.sql.trim().isEmpty) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'sql is required',
          context: {'reason': 'missing_sql'},
        ),
      );
    }
    if (command.intervalSeconds < ConnectionConstants.sqlObserverMinInterval.inSeconds ||
        command.intervalSeconds > ConnectionConstants.sqlObserverMaxInterval.inSeconds) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'interval_seconds is outside the supported range',
          context: {
            'reason': 'invalid_interval_seconds',
            'min_interval_seconds': ConnectionConstants.sqlObserverMinInterval.inSeconds,
            'max_interval_seconds': ConnectionConstants.sqlObserverMaxInterval.inSeconds,
          },
        ),
      );
    }
    if (command.idempotencyKey != null && command.idempotencyKey!.trim().isNotEmpty) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'idempotency_key is not supported for observer.register',
          context: {'reason': 'observer_idempotency_not_supported'},
        ),
      );
    }
    if (command.condition != SqlObserverCondition.rowsPresent) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'condition.type must be rows_present',
          context: {'reason': 'unsupported_observer_condition'},
        ),
      );
    }

    return SqlValidator.validateSqlForExecution(
      command.sql,
      allowMultipleStatements: command.expectMultipleResults,
    );
  }

  Future<Result<void>> _authorizeCommand(SqlObserverRegisterCommand command) async {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return const Success(unit);
    }
    final token = command.clientToken;
    if (token == null || token.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Client token is required for SQL observer registration',
          context: {
            'authentication': true,
            'reason': 'missing_client_token',
          },
        ),
      );
    }

    final statements = command.expectMultipleResults
        ? sqlStatementsForClientTokenAuthorization(command.sql)
        : <String>[command.sql];
    final authorizedFingerprints = <String>{};
    for (final raw in statements) {
      final statement = raw.trim();
      if (statement.isEmpty) {
        continue;
      }
      final fingerprint = hashClientCredentialToken(statement);
      if (authorizedFingerprints.contains(fingerprint)) {
        continue;
      }
      authorizedFingerprints.add(fingerprint);
      final result = await _authorizeSqlOperation(
        token: token,
        sql: statement,
        requestDatabase: command.database,
        requestId: command.sourceRpcRequestId,
        method: 'observer.register',
      );
      if (result.isError()) {
        return result;
      }
    }
    return const Success(unit);
  }

  Future<_SqlObserverExecutionResult> _executeObserver(
    _SqlObserverRegistration observer,
  ) async {
    final startedAt = _now();
    try {
      final request = QueryRequest(
        id: _uuid.v4(),
        agentId: observer.agentId,
        query: observer.sql,
        parameters: observer.parameters,
        timestamp: startedAt,
        clientToken: observer.clientToken,
        expectMultipleResults: observer.expectMultipleResults,
        sqlHandlingMode: observer.sqlHandlingMode,
        sourceRpcRequestId: 'observer:${observer.observerId}',
      );
      final result = await _databaseGateway.executeQuery(
        request,
        database: observer.database,
      );
      return result.fold(
        (response) {
          final normalized = _normalizerService.normalize(response);
          return _SqlObserverExecutionResult.success(
            _buildNotificationPayload(
              observer: observer,
              response: normalized,
              startedAt: startedAt,
              finishedAt: _now(),
            ),
          );
        },
        (failure) => _SqlObserverExecutionResult.failure(failure as domain.Failure),
      );
    } on Exception catch (error, stackTrace) {
      AppLogger.error(
        'SQL observer execution failed',
        error,
        stackTrace,
      );
      return _SqlObserverExecutionResult.failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL observer execution failed',
          cause: error,
          context: {
            'operation': 'sql_observer_execute',
            'observer_id': observer.observerId,
          },
        ),
      );
    }
  }

  Map<String, dynamic>? _buildNotificationPayload({
    required _SqlObserverRegistration observer,
    required QueryResponse response,
    required DateTime startedAt,
    required DateTime finishedAt,
  }) {
    var normalized = response;
    var multiResultSetsTruncated = false;
    if (normalized.resultSets.isNotEmpty) {
      final limitedSets = <QueryResultSet>[];
      var remaining = observer.maxRows;
      for (final set in normalized.resultSets) {
        if (remaining <= 0) {
          limitedSets.add(set.copyWith(rows: const [], rowCount: 0));
          multiResultSetsTruncated = multiResultSetsTruncated || set.rows.isNotEmpty;
          continue;
        }
        final rows = truncateSqlResultRows(set.rows, remaining);
        remaining -= rows.length;
        multiResultSetsTruncated = multiResultSetsTruncated || rows.length != set.rows.length;
        limitedSets.add(set.copyWith(rows: rows, rowCount: rows.length));
      }
      normalized = QueryResponse(
        id: normalized.id,
        requestId: normalized.requestId,
        agentId: normalized.agentId,
        data: limitedSets.expand((set) => set.rows).toList(growable: false),
        timestamp: normalized.timestamp,
        affectedRows: normalized.affectedRows,
        error: normalized.error,
        columnMetadata: normalized.columnMetadata,
        pagination: normalized.pagination,
        resultSets: limitedSets,
        items: normalized.items,
      );
    }

    final limitedRows = normalized.resultSets.isNotEmpty
        ? normalized.data
        : truncateSqlResultRows(normalized.data, observer.maxRows);
    if (!_hasRows(normalized, limitedRows)) {
      return null;
    }

    final wasTruncated =
        multiResultSetsTruncated || (!normalized.resultSets.isNotEmpty && limitedRows.length != normalized.data.length);
    final payload = <String, dynamic>{
      'observer_id': observer.observerId,
      'sequence': observer.nextSequence(),
      'triggered_at': finishedAt.toIso8601String(),
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
      'interval_seconds': observer.interval.inSeconds,
      'condition': SqlObserverCondition.rowsPresent.toJson(),
      'row_count': limitedRows.length,
      'returned_rows': limitedRows.length,
      'rows': limitedRows,
      if (observer.database != null) 'database': observer.database,
      if (normalized.columnMetadata != null) 'column_metadata': normalized.columnMetadata,
      if (wasTruncated) 'truncated': true,
    };

    if (normalized.resultSets.isNotEmpty) {
      payload['result_sets'] = normalized.resultSets
          .map(
            (set) => {
              'index': set.index,
              'rows': set.rows,
              'row_count': set.rows.length,
              if (set.affectedRows != null) 'affected_rows': set.affectedRows,
              if (set.columnMetadata != null) 'column_metadata': set.columnMetadata,
            },
          )
          .toList(growable: false);
    }

    return payload;
  }

  bool _hasRows(QueryResponse response, List<Map<String, dynamic>> limitedRows) {
    if (limitedRows.isNotEmpty) {
      return true;
    }
    return response.resultSets.any((set) => set.rows.isNotEmpty);
  }

  Future<void> _emitObserverEvent(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final emitter = _emitEvent;
    if (emitter == null) {
      AppLogger.warning('SQL observer event dropped because socket emitter is not available');
      return;
    }
    await emitter(event, payload);
  }
}

enum SqlObserverCondition {
  rowsPresent
  ;

  static SqlObserverCondition? fromJson(dynamic value) {
    if (value == null) {
      return rowsPresent;
    }
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final type = value['type'];
    return type == 'rows_present' ? rowsPresent : null;
  }

  Map<String, dynamic> toJson() => const {'type': 'rows_present'};
}

final class SqlObserverRegisterCommand {
  const SqlObserverRegisterCommand({
    required this.agentId,
    required this.sql,
    required this.intervalSeconds,
    required this.limits,
    required this.condition,
    this.parameters,
    this.database,
    this.clientToken,
    this.idempotencyKey,
    this.runImmediately = false,
    this.sqlHandlingMode = SqlHandlingMode.managed,
    this.expectMultipleResults = false,
    this.sourceRpcRequestId,
  });

  final String agentId;
  final String sql;
  final Map<String, dynamic>? parameters;
  final String? database;
  final String? clientToken;
  final String? idempotencyKey;
  final bool runImmediately;
  final int intervalSeconds;
  final TransportLimits limits;
  final SqlObserverCondition condition;
  final SqlHandlingMode sqlHandlingMode;
  final bool expectMultipleResults;
  final String? sourceRpcRequestId;
}

final class SqlObserverRegisterResult {
  const SqlObserverRegisterResult({
    required this.observerId,
    required this.intervalSeconds,
    required this.condition,
    required this.createdAt,
    required this.nextRunAt,
  });

  final String observerId;
  final int intervalSeconds;
  final SqlObserverCondition condition;
  final DateTime createdAt;
  final DateTime nextRunAt;

  Map<String, dynamic> toJson() => {
    'observer_id': observerId,
    'interval_seconds': intervalSeconds,
    'condition': condition.toJson(),
    'created_at': createdAt.toIso8601String(),
    'next_run_at': nextRunAt.toIso8601String(),
  };
}

final class SqlObserverUnregisterResult {
  const SqlObserverUnregisterResult({
    required this.observerId,
    required this.cancelled,
  });

  final String observerId;
  final bool cancelled;

  Map<String, dynamic> toJson() => {
    'observer_id': observerId,
    'cancelled': cancelled,
  };
}

final class SqlObserverSnapshot {
  const SqlObserverSnapshot({
    required this.observerId,
    required this.intervalSeconds,
    required this.condition,
    required this.createdAt,
    required this.nextRunAt,
    required this.consecutiveFailures,
    this.lastRunAt,
    this.lastStatus,
  });

  final String observerId;
  final int intervalSeconds;
  final SqlObserverCondition condition;
  final DateTime createdAt;
  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final String? lastStatus;
  final int consecutiveFailures;

  Map<String, dynamic> toJson() => {
    'observer_id': observerId,
    'interval_seconds': intervalSeconds,
    'condition': condition.toJson(),
    'created_at': createdAt.toIso8601String(),
    'next_run_at': nextRunAt.toIso8601String(),
    if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
    if (lastStatus != null) 'last_status': lastStatus,
    'consecutive_failures': consecutiveFailures,
  };
}

final class _SqlObserverRegistration {
  _SqlObserverRegistration({
    required this.observerId,
    required this.agentId,
    required this.sql,
    required this.interval,
    required this.maxRows,
    required this.sqlHandlingMode,
    required this.expectMultipleResults,
    required this.createdAt,
    required this.nextRunAt,
    required this.emitEvent,
    required this.execute,
    required this.now,
    this.parameters,
    this.database,
    this.clientToken,
  });

  final String observerId;
  final String agentId;
  final String sql;
  final Map<String, dynamic>? parameters;
  final String? database;
  final String? clientToken;
  final Duration interval;
  final int maxRows;
  final SqlHandlingMode sqlHandlingMode;
  final bool expectMultipleResults;
  final DateTime createdAt;
  final Future<void> Function(String event, Map<String, dynamic> payload) emitEvent;
  final Future<_SqlObserverExecutionResult> Function(_SqlObserverRegistration observer) execute;
  final DateTime Function() now;

  Timer? _timer;
  bool _isRunning = false;
  int _sequence = 0;
  DateTime nextRunAt;
  DateTime? lastRunAt;
  String? lastStatus;
  int consecutiveFailures = 0;

  void start({required bool runImmediately}) {
    if (runImmediately) {
      unawaited(runOnce());
    }
    _timer = Timer.periodic(interval, (_) {
      nextRunAt = now().add(interval);
      unawaited(runOnce());
    });
  }

  Future<void> runOnce() async {
    if (_isRunning) {
      lastStatus = 'skipped_overlap';
      return;
    }
    _isRunning = true;
    lastRunAt = now();
    try {
      final result = await execute(this);
      if (result.failure != null) {
        consecutiveFailures++;
        lastStatus = 'error';
        await emitEvent(
          'observer:error',
          _buildErrorPayload(result.failure!),
        );
        return;
      }
      final payload = result.notificationPayload;
      consecutiveFailures = 0;
      lastStatus = payload == null ? 'empty' : 'notified';
      if (payload != null) {
        await emitEvent('observer:notification', payload);
      }
    } finally {
      _isRunning = false;
    }
  }

  int nextSequence() {
    return ++_sequence;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  SqlObserverSnapshot snapshot() {
    return SqlObserverSnapshot(
      observerId: observerId,
      intervalSeconds: interval.inSeconds,
      condition: SqlObserverCondition.rowsPresent,
      createdAt: createdAt,
      nextRunAt: nextRunAt,
      lastRunAt: lastRunAt,
      lastStatus: lastStatus,
      consecutiveFailures: consecutiveFailures,
    );
  }

  Map<String, dynamic> _buildErrorPayload(domain.Failure failure) {
    final occurredAt = now();
    final rpcError = FailureToRpcErrorMapper.map(
      failure,
      instance: observerId,
    );
    final errorData = rpcError.data;
    final reason = errorData is Map<String, dynamic> ? errorData['reason'] as String? : null;
    return {
      'observer_id': observerId,
      'sequence': nextSequence(),
      'occurred_at': occurredAt.toIso8601String(),
      'consecutive_failures': consecutiveFailures,
      'retry_at': occurredAt.add(interval).toIso8601String(),
      'error': rpcError.toJson(),
      'reason': reason ?? RpcErrorCode.getReason(rpcError.code),
    };
  }
}

final class _SqlObserverExecutionResult {
  const _SqlObserverExecutionResult._({
    this.notificationPayload,
    this.failure,
  });

  factory _SqlObserverExecutionResult.success(
    Map<String, dynamic>? notificationPayload,
  ) => _SqlObserverExecutionResult._(notificationPayload: notificationPayload);

  factory _SqlObserverExecutionResult.failure(domain.Failure failure) =>
      _SqlObserverExecutionResult._(failure: failure);

  final Map<String, dynamic>? notificationPayload;
  final domain.Failure? failure;
}
