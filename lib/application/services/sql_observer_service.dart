import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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
  int _registeredTotal = 0;
  int _unregisteredTotal = 0;

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
      condition: command.condition,
      notificationPolicy: command.notificationPolicy,
      executionTimeout: command.executionTimeout,
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
    _registeredTotal++;
    observer.start(runImmediately: command.runImmediately);

    return Success(
      SqlObserverRegisterResult(
        observerId: observerId,
        intervalSeconds: command.intervalSeconds,
        condition: command.condition,
        notificationPolicy: command.notificationPolicy,
        executionTimeout: command.executionTimeout,
        persistenceMode: command.persistenceMode,
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
    _unregisteredTotal++;
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

  Future<Result<void>> runOnce(String observerId) async {
    final observer = _observers[observerId];
    if (observer == null) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'observer_id was not found',
          context: {
            'reason': 'observer_not_found',
            'observer_id': observerId,
          },
        ),
      );
    }
    await observer.runOnce();
    return const Success(unit);
  }

  SqlObserverMetricsSnapshot metricsSnapshot() {
    var ticksTotal = 0;
    var notificationsTotal = 0;
    var errorsTotal = 0;
    var skippedOverlapTotal = 0;
    var totalLatencyMs = 0;
    var latencySamples = 0;

    for (final observer in _observers.values) {
      ticksTotal += observer.ticksTotal;
      notificationsTotal += observer.notificationsTotal;
      errorsTotal += observer.errorsTotal;
      skippedOverlapTotal += observer.skippedOverlapTotal;
      final avgLatency = observer.averageLatencyMs;
      if (avgLatency != null) {
        totalLatencyMs += avgLatency;
        latencySamples++;
      }
    }

    return SqlObserverMetricsSnapshot(
      active: _observers.length,
      registeredTotal: _registeredTotal,
      unregisteredTotal: _unregisteredTotal,
      ticksTotal: ticksTotal,
      notificationsTotal: notificationsTotal,
      errorsTotal: errorsTotal,
      skippedOverlapTotal: skippedOverlapTotal,
      averageLatencyMs: latencySamples == 0 ? 0 : totalLatencyMs ~/ latencySamples,
    );
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
    final conditionValidation = command.condition.validate();
    if (conditionValidation.isError()) {
      return conditionValidation;
    }
    final policyValidation = command.notificationPolicy.validate();
    if (policyValidation.isError()) {
      return policyValidation;
    }
    if (command.persistenceMode != SqlObserverPersistenceMode.session) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Only session persistence is supported for SQL observers',
          context: {'reason': 'unsupported_observer_persistence'},
        ),
      );
    }
    if (command.executionTimeout < ConnectionConstants.sqlObserverMinExecutionTimeout ||
        command.executionTimeout > ConnectionConstants.sqlObserverMaxExecutionTimeout) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'execution_timeout_seconds is outside the supported range',
          context: {
            'reason': 'invalid_execution_timeout_seconds',
            'min_execution_timeout_seconds': ConnectionConstants.sqlObserverMinExecutionTimeout.inSeconds,
            'max_execution_timeout_seconds': ConnectionConstants.sqlObserverMaxExecutionTimeout.inSeconds,
          },
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
      final result = await _databaseGateway
          .executeQuery(
            request,
            timeout: observer.executionTimeout,
            database: observer.database,
          )
          .timeout(observer.executionTimeout);
      return result.fold(
        (response) {
          final normalized = _normalizerService.normalize(response);
          return _SqlObserverExecutionResult.success(
            _buildNotificationCandidate(
              observer: observer,
              response: normalized,
              startedAt: startedAt,
              finishedAt: _now(),
            ),
          );
        },
        (failure) => _SqlObserverExecutionResult.failure(failure as domain.Failure),
      );
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.warning(
        'SQL observer execution timed out',
        error,
        stackTrace,
      );
      return _SqlObserverExecutionResult.failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL observer execution timeout',
          cause: error,
          context: {
            'operation': 'sql_observer_execute',
            'observer_id': observer.observerId,
            'timeout': true,
            'timeout_stage': 'sql',
            'reason': 'sql_observer_timeout',
            'timeout_seconds': observer.executionTimeout.inSeconds,
          },
        ),
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

  _SqlObserverExecutionSuccess _buildNotificationCandidate({
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

    final actualRowCount = _actualRowCount(normalized);
    final limitedRows = normalized.resultSets.isNotEmpty
        ? normalized.data
        : truncateSqlResultRows(normalized.data, observer.maxRows);
    final conditionMet = observer.condition.evaluate(actualRowCount);

    final wasTruncated =
        multiResultSetsTruncated || (!normalized.resultSets.isNotEmpty && limitedRows.length != normalized.data.length);
    final payload = <String, dynamic>{
      'observer_id': observer.observerId,
      'triggered_at': finishedAt.toIso8601String(),
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
      'interval_seconds': observer.interval.inSeconds,
      'condition': observer.condition.toJson(),
      'notification_policy': observer.notificationPolicy.toJson(),
      'execution_timeout_seconds': observer.executionTimeout.inSeconds,
      'persistence': observer.persistenceMode.toJson(),
      'row_count': actualRowCount,
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

    return _SqlObserverExecutionSuccess(
      payload: conditionMet ? payload : null,
      rowCount: actualRowCount,
      returnedRows: limitedRows.length,
      conditionMet: conditionMet,
      resultSignature: _stableResultSignature(normalized, limitedRows),
      elapsed: finishedAt.difference(startedAt),
    );
  }

  int _actualRowCount(QueryResponse response) {
    if (response.resultSets.isNotEmpty) {
      return response.resultSets.fold<int>(0, (total, set) => total + set.rows.length);
    }
    return response.data.length;
  }

  String _stableResultSignature(QueryResponse response, List<Map<String, dynamic>> limitedRows) {
    final data = response.resultSets.isNotEmpty
        ? response.resultSets
              .map(
                (set) => {
                  'index': set.index,
                  'rows': set.rows,
                  'affected_rows': set.affectedRows,
                },
              )
              .toList(growable: false)
        : limitedRows;
    return sha256.convert(utf8.encode(jsonEncode(data))).toString();
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

final class SqlObserverCondition {
  const SqlObserverCondition._({
    required this.type,
    this.minRows,
  });

  const SqlObserverCondition.rowCountGreaterThan(int minRows)
    : this._(
        type: 'row_count_gt',
        minRows: minRows,
      );

  static const rowsPresent = SqlObserverCondition._(type: 'rows_present');

  static SqlObserverCondition? fromJson(dynamic value) {
    if (value == null) {
      return rowsPresent;
    }
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final type = value['type'];
    return switch (type) {
      'rows_present' => rowsPresent,
      'row_count_gt' =>
        value['min_rows'] is int
            ? SqlObserverCondition._(
                type: 'row_count_gt',
                minRows: value['min_rows'] as int,
              )
            : null,
      _ => null,
    };
  }

  final String type;
  final int? minRows;

  bool evaluate(int rowCount) {
    return switch (type) {
      'rows_present' => rowCount > 0,
      'row_count_gt' => rowCount > (minRows ?? 0),
      _ => false,
    };
  }

  Result<void> validate() {
    if (type == 'rows_present') {
      return const Success(unit);
    }
    if (type == 'row_count_gt' && minRows != null && minRows! >= 0) {
      return const Success(unit);
    }
    return Failure(
      domain.ValidationFailure.withContext(
        message: 'Unsupported SQL observer condition',
        context: {'reason': 'unsupported_observer_condition'},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (minRows != null) 'min_rows': minRows,
  };
}

enum SqlObserverNotificationMode {
  everyTick('every_tick'),
  onceUntilEmpty('once_until_empty'),
  onChange('on_change')
  ;

  const SqlObserverNotificationMode(this.wireName);

  final String wireName;

  static SqlObserverNotificationMode? fromJson(dynamic value) {
    if (value == null) {
      return everyTick;
    }
    if (value is! String) {
      return null;
    }
    for (final mode in values) {
      if (mode.wireName == value) {
        return mode;
      }
    }
    return null;
  }
}

final class SqlObserverNotificationPolicy {
  const SqlObserverNotificationPolicy({
    this.mode = SqlObserverNotificationMode.everyTick,
    this.minInterval,
  });

  static const defaults = SqlObserverNotificationPolicy();

  static SqlObserverNotificationPolicy? fromJson(dynamic value) {
    if (value == null) {
      return defaults;
    }
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final mode = SqlObserverNotificationMode.fromJson(value['mode']);
    if (mode == null) {
      return null;
    }
    final rawMinInterval = value['min_interval_seconds'];
    if (rawMinInterval != null && rawMinInterval is! int) {
      return null;
    }
    return SqlObserverNotificationPolicy(
      mode: mode,
      minInterval: rawMinInterval == null ? null : Duration(seconds: rawMinInterval as int),
    );
  }

  final SqlObserverNotificationMode mode;
  final Duration? minInterval;

  Result<void> validate() {
    final minInterval = this.minInterval;
    if (minInterval != null && minInterval.isNegative) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'notification_policy.min_interval_seconds must be non-negative',
          context: {'reason': 'invalid_notification_min_interval'},
        ),
      );
    }
    return const Success(unit);
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.wireName,
    if (minInterval != null) 'min_interval_seconds': minInterval!.inSeconds,
  };
}

enum SqlObserverPersistenceMode {
  session('session')
  ;

  const SqlObserverPersistenceMode(this.wireName);

  final String wireName;

  static SqlObserverPersistenceMode? fromJson(dynamic value) {
    if (value == null) {
      return session;
    }
    if (value is String) {
      for (final mode in values) {
        if (mode.wireName == value) {
          return mode;
        }
      }
      return null;
    }
    if (value is Map<String, dynamic>) {
      return fromJson(value['mode']);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'mode': wireName};
}

final class SqlObserverRegisterCommand {
  const SqlObserverRegisterCommand({
    required this.agentId,
    required this.sql,
    required this.intervalSeconds,
    required this.limits,
    required this.condition,
    this.notificationPolicy = SqlObserverNotificationPolicy.defaults,
    this.executionTimeout = ConnectionConstants.sqlObserverDefaultExecutionTimeout,
    this.persistenceMode = SqlObserverPersistenceMode.session,
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
  final SqlObserverNotificationPolicy notificationPolicy;
  final Duration executionTimeout;
  final SqlObserverPersistenceMode persistenceMode;
  final SqlHandlingMode sqlHandlingMode;
  final bool expectMultipleResults;
  final String? sourceRpcRequestId;
}

final class SqlObserverRegisterResult {
  const SqlObserverRegisterResult({
    required this.observerId,
    required this.intervalSeconds,
    required this.condition,
    required this.notificationPolicy,
    required this.executionTimeout,
    required this.persistenceMode,
    required this.createdAt,
    required this.nextRunAt,
  });

  final String observerId;
  final int intervalSeconds;
  final SqlObserverCondition condition;
  final SqlObserverNotificationPolicy notificationPolicy;
  final Duration executionTimeout;
  final SqlObserverPersistenceMode persistenceMode;
  final DateTime createdAt;
  final DateTime nextRunAt;

  Map<String, dynamic> toJson() => {
    'observer_id': observerId,
    'interval_seconds': intervalSeconds,
    'condition': condition.toJson(),
    'notification_policy': notificationPolicy.toJson(),
    'execution_timeout_seconds': executionTimeout.inSeconds,
    'persistence': persistenceMode.toJson(),
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
    required this.notificationPolicy,
    required this.executionTimeout,
    required this.persistenceMode,
    required this.createdAt,
    required this.nextRunAt,
    required this.consecutiveFailures,
    required this.sequence,
    required this.ticksTotal,
    required this.notificationsTotal,
    required this.errorsTotal,
    required this.skippedOverlapTotal,
    this.lastNotificationAt,
    this.lastRowCount,
    this.lastReturnedRows,
    this.lastLatencyMs,
    this.averageLatencyMs,
    this.lastError,
    this.lastRunAt,
    this.lastStatus,
  });

  final String observerId;
  final int intervalSeconds;
  final SqlObserverCondition condition;
  final SqlObserverNotificationPolicy notificationPolicy;
  final Duration executionTimeout;
  final SqlObserverPersistenceMode persistenceMode;
  final DateTime createdAt;
  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final DateTime? lastNotificationAt;
  final String? lastStatus;
  final int consecutiveFailures;
  final int sequence;
  final int ticksTotal;
  final int notificationsTotal;
  final int errorsTotal;
  final int skippedOverlapTotal;
  final int? lastRowCount;
  final int? lastReturnedRows;
  final int? lastLatencyMs;
  final int? averageLatencyMs;
  final Map<String, dynamic>? lastError;

  Map<String, dynamic> toJson() => {
    'observer_id': observerId,
    'interval_seconds': intervalSeconds,
    'condition': condition.toJson(),
    'notification_policy': notificationPolicy.toJson(),
    'execution_timeout_seconds': executionTimeout.inSeconds,
    'persistence': persistenceMode.toJson(),
    'created_at': createdAt.toIso8601String(),
    'next_run_at': nextRunAt.toIso8601String(),
    if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
    if (lastNotificationAt != null) 'last_notification_at': lastNotificationAt!.toIso8601String(),
    if (lastStatus != null) 'last_status': lastStatus,
    'consecutive_failures': consecutiveFailures,
    'sequence': sequence,
    'ticks_total': ticksTotal,
    'notifications_total': notificationsTotal,
    'errors_total': errorsTotal,
    'skipped_overlap_total': skippedOverlapTotal,
    if (lastRowCount != null) 'last_row_count': lastRowCount,
    if (lastReturnedRows != null) 'last_returned_rows': lastReturnedRows,
    if (lastLatencyMs != null) 'last_latency_ms': lastLatencyMs,
    if (averageLatencyMs != null) 'average_latency_ms': averageLatencyMs,
    if (lastError != null) 'last_error': lastError,
  };
}

final class SqlObserverMetricsSnapshot {
  const SqlObserverMetricsSnapshot({
    required this.active,
    required this.registeredTotal,
    required this.unregisteredTotal,
    required this.ticksTotal,
    required this.notificationsTotal,
    required this.errorsTotal,
    required this.skippedOverlapTotal,
    required this.averageLatencyMs,
  });

  final int active;
  final int registeredTotal;
  final int unregisteredTotal;
  final int ticksTotal;
  final int notificationsTotal;
  final int errorsTotal;
  final int skippedOverlapTotal;
  final int averageLatencyMs;

  Map<String, Object?> toJson() => {
    'active': active,
    'registered_total': registeredTotal,
    'unregistered_total': unregisteredTotal,
    'ticks_total': ticksTotal,
    'notifications_total': notificationsTotal,
    'errors_total': errorsTotal,
    'skipped_overlap_total': skippedOverlapTotal,
    'avg_latency_ms': averageLatencyMs,
  };
}

final class _SqlObserverRegistration {
  _SqlObserverRegistration({
    required this.observerId,
    required this.agentId,
    required this.sql,
    required this.interval,
    required this.condition,
    required this.notificationPolicy,
    required this.executionTimeout,
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
  final SqlObserverCondition condition;
  final SqlObserverNotificationPolicy notificationPolicy;
  final Duration executionTimeout;
  final SqlObserverPersistenceMode persistenceMode = SqlObserverPersistenceMode.session;
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
  int ticksTotal = 0;
  int _latencySamples = 0;
  int notificationsTotal = 0;
  int errorsTotal = 0;
  int skippedOverlapTotal = 0;
  int _totalLatencyMs = 0;
  DateTime nextRunAt;
  DateTime? lastRunAt;
  DateTime? lastNotificationAt;
  String? lastStatus;
  int? lastRowCount;
  int? lastReturnedRows;
  int? lastLatencyMs;
  String? _lastNotifiedSignature;
  bool _wasConditionMet = false;
  Map<String, dynamic>? lastError;
  int consecutiveFailures = 0;

  int? get averageLatencyMs => _latencySamples == 0 ? null : _totalLatencyMs ~/ _latencySamples;

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
      skippedOverlapTotal++;
      return;
    }
    _isRunning = true;
    ticksTotal++;
    lastRunAt = now();
    try {
      final result = await execute(this);
      if (result.failure != null) {
        consecutiveFailures++;
        errorsTotal++;
        lastStatus = 'error';
        final errorPayload = _buildErrorPayload(result.failure!);
        lastError = errorPayload['error'] as Map<String, dynamic>?;
        await emitEvent('observer:error', errorPayload);
        return;
      }
      final success = result.success!;
      lastRowCount = success.rowCount;
      lastReturnedRows = success.returnedRows;
      lastLatencyMs = success.elapsed.inMilliseconds;
      _totalLatencyMs += success.elapsed.inMilliseconds;
      _latencySamples++;
      consecutiveFailures = 0;
      lastError = null;

      final payload = success.payload;
      if (payload == null) {
        _wasConditionMet = false;
        lastStatus = success.conditionMet ? 'suppressed' : 'condition_not_met';
        return;
      }

      if (!_shouldNotify(success)) {
        _wasConditionMet = success.conditionMet;
        lastStatus = 'suppressed';
        return;
      }

      _wasConditionMet = success.conditionMet;
      _lastNotifiedSignature = success.resultSignature;
      final sequence = nextSequence();
      final notificationId = '${observerId}_$sequence';
      lastNotificationAt = now();
      notificationsTotal++;
      lastStatus = 'notified';
      await emitEvent(
        'observer:notification',
        {
          ...payload,
          'notification_id': notificationId,
          'sequence': sequence,
          'delivery': {
            'mode': 'ack_retry',
            'attempt': 1,
          },
        },
      );
    } finally {
      _isRunning = false;
    }
  }

  bool _shouldNotify(_SqlObserverExecutionSuccess success) {
    final minInterval = notificationPolicy.minInterval;
    final lastNotificationAt = this.lastNotificationAt;
    if (minInterval != null && lastNotificationAt != null && now().difference(lastNotificationAt) < minInterval) {
      return false;
    }

    return switch (notificationPolicy.mode) {
      SqlObserverNotificationMode.everyTick => true,
      SqlObserverNotificationMode.onceUntilEmpty => !_wasConditionMet,
      SqlObserverNotificationMode.onChange => _lastNotifiedSignature != success.resultSignature,
    };
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
      condition: condition,
      notificationPolicy: notificationPolicy,
      executionTimeout: executionTimeout,
      persistenceMode: persistenceMode,
      createdAt: createdAt,
      nextRunAt: nextRunAt,
      lastRunAt: lastRunAt,
      lastNotificationAt: lastNotificationAt,
      lastStatus: lastStatus,
      consecutiveFailures: consecutiveFailures,
      sequence: _sequence,
      ticksTotal: ticksTotal,
      notificationsTotal: notificationsTotal,
      errorsTotal: errorsTotal,
      skippedOverlapTotal: skippedOverlapTotal,
      lastRowCount: lastRowCount,
      lastReturnedRows: lastReturnedRows,
      lastLatencyMs: lastLatencyMs,
      averageLatencyMs: averageLatencyMs,
      lastError: lastError,
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
    final sequence = nextSequence();
    return {
      'observer_id': observerId,
      'sequence': sequence,
      'notification_id': '${observerId}_$sequence',
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
    this.success,
    this.failure,
  });

  factory _SqlObserverExecutionResult.success(
    _SqlObserverExecutionSuccess success,
  ) => _SqlObserverExecutionResult._(success: success);

  factory _SqlObserverExecutionResult.failure(domain.Failure failure) =>
      _SqlObserverExecutionResult._(failure: failure);

  final _SqlObserverExecutionSuccess? success;
  final domain.Failure? failure;
}

final class _SqlObserverExecutionSuccess {
  const _SqlObserverExecutionSuccess({
    required this.payload,
    required this.rowCount,
    required this.returnedRows,
    required this.conditionMet,
    required this.resultSignature,
    required this.elapsed,
  });

  final Map<String, dynamic>? payload;
  final int rowCount;
  final int returnedRows;
  final bool conditionMet;
  final String resultSignature;
  final Duration elapsed;
}
