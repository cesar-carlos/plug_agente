import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';

/// Servico para coletar e gerenciar metricas de performance.
///
/// Chaves em [_eventCounters] sao estaveis para exportacao (ex.: OpenTelemetry).
class MetricsCollector implements IMetricsCollector {
  MetricsCollector();

  static const String _timeoutCancelSuccessCounter = 'timeout_cancel_success';
  static const String _timeoutCancelFailureCounter = 'timeout_cancel_failure';
  static const String _transactionRollbackFailureCounter = 'transaction_rollback_failure';
  static const String _idempotencyFingerprintMismatchCounter = 'idempotency_fingerprint_mismatch';
  static const String _multiResultPoolVacuousFallbackCounter = 'multi_result_pool_vacuous_fallback';
  static const String _multiResultDirectStillVacuousCounter = 'multi_result_direct_still_vacuous';
  static const String _transactionalBatchDirectPathCounter = 'transactional_batch_direct_path';
  static const String _authDecisionCacheHitCounter = 'auth_decision_cache_hit';
  static const String _authDecisionCacheMissCounter = 'auth_decision_cache_miss';
  static const String _authPolicyCacheHitCounter = 'auth_policy_cache_hit';
  static const String _authPolicyCacheMissCounter = 'auth_policy_cache_miss';
  static const String _rpcSqlExecuteStreamingChunksResponseCounter = 'rpc_sql_execute_streaming_chunks_response';
  static const String _rpcSqlExecuteStreamingFromDbResponseCounter = 'rpc_sql_execute_streaming_from_db_response';
  static const String _rpcSqlExecuteMaterializedResponseCounter = 'rpc_sql_execute_materialized_response';
  static const String _rpcStreamTerminalCompleteEmittedCounter = 'rpc_stream_terminal_complete_emitted';
  static const String _rpcStreamTerminalCompleteFailedCounter = 'rpc_stream_terminal_complete_failed';
  static const String _rpcResponseAckRetryCounter = 'rpc_response_ack_retry';
  static const String _rpcResponseAckFallbackWithoutAckCounter = 'rpc_response_ack_fallback_without_ack';
  static const String _rpcClientTokenGetPolicySuccessCounter = 'rpc_client_token_get_policy_success';
  static const String _rpcClientTokenGetPolicyFailureCounter = 'rpc_client_token_get_policy_failure';
  static const String _rpcClientTokenGetPolicyFailureValidationCounter = 'rpc_client_token_get_policy_failure_validation';
  static const String _rpcClientTokenGetPolicyFailureNetworkCounter = 'rpc_client_token_get_policy_failure_network';
  static const String _rpcClientTokenGetPolicyFailureServerCounter = 'rpc_client_token_get_policy_failure_server';
  static const String _rpcClientTokenGetPolicyFailureNotFoundCounter = 'rpc_client_token_get_policy_failure_not_found';
  static const String _rpcClientTokenGetPolicyFailureConnectionCounter = 'rpc_client_token_get_policy_failure_connection';
  static const String _rpcClientTokenGetPolicyFailureDatabaseCounter = 'rpc_client_token_get_policy_failure_database';
  static const String _rpcClientTokenGetPolicyFailureConfigurationCounter = 'rpc_client_token_get_policy_failure_configuration';
  static const String _rpcClientTokenGetPolicyFailureQueryCounter = 'rpc_client_token_get_policy_failure_query';
  static const String _rpcClientTokenGetPolicyFailureCompressionCounter = 'rpc_client_token_get_policy_failure_compression';
  static const String _rpcClientTokenGetPolicyFailureNotificationCounter = 'rpc_client_token_get_policy_failure_notification';
  static const String _rpcClientTokenGetPolicyFailureOtherCounter = 'rpc_client_token_get_policy_failure_other';
  static const String _rpcClientTokenGetPolicyRateLimitedCounter = 'rpc_client_token_get_policy_rate_limited';
  static const String _poolAcquireTimeoutCounter = 'pool_acquire_timeout';
  static const String _connectTimeoutCounter = 'connect_timeout';
  static const String _queryTimeoutCounter = 'query_timeout';
  static const String _preparedStatementReuseCounter = 'prepared_statement_reuse';

  static const int _maxMetrics = 10000;

  final List<QueryMetrics> _metrics = [];
  final _metricsController = StreamController<QueryMetrics>.broadcast();
  final Map<String, int> _eventCounters = <String, int>{};

  @override
  Stream<QueryMetrics> get metricsStream => _metricsController.stream;

  @override
  List<QueryMetrics> get metrics => List.unmodifiable(_metrics);

  /// Numero de metricas coletadas.
  int get count => _metrics.length;
  int get timeoutCancelSuccessCount => _eventCounters[_timeoutCancelSuccessCounter] ?? 0;
  int get timeoutCancelFailureCount => _eventCounters[_timeoutCancelFailureCounter] ?? 0;
  int get transactionRollbackFailureCount => _eventCounters[_transactionRollbackFailureCounter] ?? 0;
  int get idempotencyFingerprintMismatchCount => _eventCounters[_idempotencyFingerprintMismatchCounter] ?? 0;
  int get multiResultPoolVacuousFallbackCount => _eventCounters[_multiResultPoolVacuousFallbackCounter] ?? 0;
  int get multiResultDirectStillVacuousCount => _eventCounters[_multiResultDirectStillVacuousCounter] ?? 0;
  int get transactionalBatchDirectPathCount => _eventCounters[_transactionalBatchDirectPathCounter] ?? 0;
  int get authDecisionCacheHitCount => _eventCounters[_authDecisionCacheHitCounter] ?? 0;
  int get authDecisionCacheMissCount => _eventCounters[_authDecisionCacheMissCounter] ?? 0;
  int get authPolicyCacheHitCount => _eventCounters[_authPolicyCacheHitCounter] ?? 0;
  int get authPolicyCacheMissCount => _eventCounters[_authPolicyCacheMissCounter] ?? 0;
  int get rpcSqlExecuteStreamingChunksResponseCount =>
      _eventCounters[_rpcSqlExecuteStreamingChunksResponseCounter] ?? 0;
  int get rpcSqlExecuteStreamingFromDbResponseCount =>
      _eventCounters[_rpcSqlExecuteStreamingFromDbResponseCounter] ?? 0;
  int get rpcSqlExecuteMaterializedResponseCount => _eventCounters[_rpcSqlExecuteMaterializedResponseCounter] ?? 0;
  int get rpcStreamTerminalCompleteEmittedCount => _eventCounters[_rpcStreamTerminalCompleteEmittedCounter] ?? 0;
  int get rpcStreamTerminalCompleteFailedCount => _eventCounters[_rpcStreamTerminalCompleteFailedCounter] ?? 0;
  int get rpcResponseAckRetryCount => _eventCounters[_rpcResponseAckRetryCounter] ?? 0;
  int get rpcResponseAckFallbackWithoutAckCount => _eventCounters[_rpcResponseAckFallbackWithoutAckCounter] ?? 0;
  int get rpcClientTokenGetPolicySuccessCount => _eventCounters[_rpcClientTokenGetPolicySuccessCounter] ?? 0;
  int get rpcClientTokenGetPolicyFailureCount => _eventCounters[_rpcClientTokenGetPolicyFailureCounter] ?? 0;
  int get rpcClientTokenGetPolicyRateLimitedCount => _eventCounters[_rpcClientTokenGetPolicyRateLimitedCounter] ?? 0;
  int get poolAcquireTimeoutCount => _eventCounters[_poolAcquireTimeoutCounter] ?? 0;
  int get connectTimeoutCount => _eventCounters[_connectTimeoutCounter] ?? 0;
  int get queryTimeoutCount => _eventCounters[_queryTimeoutCounter] ?? 0;
  int get preparedStatementReuseCount => _eventCounters[_preparedStatementReuseCounter] ?? 0;

  Map<String, int> get eventCounters => UnmodifiableMapView<String, int>(_eventCounters);

  /// Limpa todas as metricas.
  void clear() {
    _metrics.clear();
    _eventCounters.clear();
  }

  void recordTimeoutCancelSuccess() => _incrementEventCounter(_timeoutCancelSuccessCounter);

  void recordTimeoutCancelFailure() => _incrementEventCounter(_timeoutCancelFailureCounter);

  void recordTransactionRollbackFailure() => _incrementEventCounter(_transactionRollbackFailureCounter);

  void recordIdempotencyFingerprintMismatch() => _incrementEventCounter(_idempotencyFingerprintMismatchCounter);

  void recordMultiResultPoolVacuousFallback() => _incrementEventCounter(_multiResultPoolVacuousFallbackCounter);

  void recordMultiResultDirectStillVacuous() => _incrementEventCounter(_multiResultDirectStillVacuousCounter);

  void recordTransactionalBatchDirectPath() => _incrementEventCounter(_transactionalBatchDirectPathCounter);

  void recordAuthDecisionCacheHit() => _incrementEventCounter(_authDecisionCacheHitCounter);

  void recordAuthDecisionCacheMiss() => _incrementEventCounter(_authDecisionCacheMissCounter);

  void recordAuthPolicyCacheHit() => _incrementEventCounter(_authPolicyCacheHitCounter);

  void recordAuthPolicyCacheMiss() => _incrementEventCounter(_authPolicyCacheMissCounter);

  void recordRpcSqlExecuteStreamingChunksResponse() =>
      _incrementEventCounter(_rpcSqlExecuteStreamingChunksResponseCounter);

  void recordRpcSqlExecuteStreamingFromDbResponse() =>
      _incrementEventCounter(_rpcSqlExecuteStreamingFromDbResponseCounter);

  void recordRpcSqlExecuteMaterializedResponse() => _incrementEventCounter(_rpcSqlExecuteMaterializedResponseCounter);

  void recordRpcStreamTerminalCompleteEmitted() => _incrementEventCounter(_rpcStreamTerminalCompleteEmittedCounter);

  void recordRpcStreamTerminalCompleteFailed() => _incrementEventCounter(_rpcStreamTerminalCompleteFailedCounter);

  void recordRpcResponseAckRetry() => _incrementEventCounter(_rpcResponseAckRetryCounter);

  void recordRpcResponseAckFallbackWithoutAck() => _incrementEventCounter(_rpcResponseAckFallbackWithoutAckCounter);

  void recordClientTokenGetPolicySuccess() => _incrementEventCounter(_rpcClientTokenGetPolicySuccessCounter);

  void recordClientTokenGetPolicyFailure(Failure failure) {
    _incrementEventCounter(_rpcClientTokenGetPolicyFailureCounter);
    final kind = switch (failure) {
      ValidationFailure _ => _rpcClientTokenGetPolicyFailureValidationCounter,
      NetworkFailure _ => _rpcClientTokenGetPolicyFailureNetworkCounter,
      ServerFailure _ => _rpcClientTokenGetPolicyFailureServerCounter,
      NotFoundFailure _ => _rpcClientTokenGetPolicyFailureNotFoundCounter,
      ConnectionFailure _ => _rpcClientTokenGetPolicyFailureConnectionCounter,
      DatabaseFailure _ => _rpcClientTokenGetPolicyFailureDatabaseCounter,
      ConfigurationFailure _ => _rpcClientTokenGetPolicyFailureConfigurationCounter,
      QueryExecutionFailure _ => _rpcClientTokenGetPolicyFailureQueryCounter,
      CompressionFailure _ => _rpcClientTokenGetPolicyFailureCompressionCounter,
      NotificationFailure _ => _rpcClientTokenGetPolicyFailureNotificationCounter,
      Failure _ => _rpcClientTokenGetPolicyFailureOtherCounter,
    };
    _incrementEventCounter(kind);
  }

  void recordClientTokenGetPolicyRateLimited() => _incrementEventCounter(_rpcClientTokenGetPolicyRateLimitedCounter);

  void recordPoolAcquireTimeout() => _incrementEventCounter(_poolAcquireTimeoutCounter);

  void recordConnectTimeout() => _incrementEventCounter(_connectTimeoutCounter);

  void recordQueryTimeout() => _incrementEventCounter(_queryTimeoutCounter);

  void recordPreparedStatementReuse() => _incrementEventCounter(_preparedStatementReuseCounter);

  /// Registra uma metrica de sucesso.
  void recordSuccess({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required int rowsAffected,
    required int columnCount,
  }) {
    final metric = QueryMetrics.success(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      rowsAffected: rowsAffected,
      columnCount: columnCount,
    );

    _addMetric(metric);
  }

  /// Registra uma metrica de falha.
  void recordFailure({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required String errorMessage,
  }) {
    final metric = QueryMetrics.failure(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      errorMessage: errorMessage,
    );

    _addMetric(metric);
  }

  @override
  MetricsSummary getSummary({int limit = 100}) {
    final recent = _metrics.length > limit ? _metrics.sublist(_metrics.length - limit) : _metrics;

    return MetricsSummary.fromList(recent);
  }

  /// Obtem metricas filtradas por sucesso/falha.
  List<QueryMetrics> getMetrics({bool? success}) {
    if (success == null) return List.unmodifiable(_metrics);

    return _metrics.where((m) => m.success == success).toList();
  }

  /// Obtem metricas acima de um tempo de execucao.
  List<QueryMetrics> getSlowQueries({
    Duration threshold = const Duration(seconds: 1),
  }) {
    return _metrics.where((m) => m.executionDuration > threshold).toList()
      ..sort((a, b) => b.executionDuration.compareTo(a.executionDuration));
  }

  /// Registra metrica e notifica listeners.
  void _addMetric(QueryMetrics metric) {
    _metrics.add(metric);
    if (_metrics.length > _maxMetrics) {
      _metrics.removeRange(0, _metrics.length - _maxMetrics);
    }

    if (!metric.success) {
      developer.log(
        'QueryMetric: ${metric.executionDuration.inMilliseconds}ms, '
        'rows: ${metric.rowsAffected}, success: false',
        name: 'metrics',
        level: 1000,
      );
    }

    if (!_metricsController.isClosed) {
      _metricsController.add(metric);
    }
  }

  void _incrementEventCounter(String counter) {
    _eventCounters[counter] = (_eventCounters[counter] ?? 0) + 1;
  }

  /// Exporta metricas para JSON.
  List<Map<String, dynamic>> exportToJson() {
    return _metrics.map((m) => m.toMap()).toList();
  }

  /// Dispose do controller.
  void dispose() {
    _metricsController.close();
  }
}
