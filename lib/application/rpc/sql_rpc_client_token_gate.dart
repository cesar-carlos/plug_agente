import 'dart:developer' as developer;

import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/sql_authorization_fingerprint.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';

class SqlRpcClientTokenGate {
  SqlRpcClientTokenGate({
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    IAuthorizationMetricsCollector? authMetrics,
    ISqlInvestigationCollector? sqlInvestigation,
  }) : _featureFlags = featureFlags,
       _support = support,
       _authMetrics = authMetrics,
       _sqlInvestigation = sqlInvestigation;

  static bool _loggedMissingClientTokenThisSession = false;

  final FeatureFlags _featureFlags;
  final SqlRpcMethodHandlerSupport _support;
  final IAuthorizationMetricsCollector? _authMetrics;
  final ISqlInvestigationCollector? _sqlInvestigation;

  /// Returns an error response when authorization blocks the request;
  /// returns null when the caller should continue.
  Future<RpcResponse?> enforce({
    required RpcRequest request,
    required String? clientToken,
    required Iterable<String> sqlStatements,
    required String investigationSqlOnDeny,
    required String? requestDatabase,
    required DateTime? deadline,
    bool deduplicateEquivalentSql = false,
    bool skipEmptyAfterTrim = false,
  }) async {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return null;
    }

    if (clientToken == null || clientToken.isEmpty) {
      _logMissingClientTokenOnce(request);
      _authMetrics?.recordDenied(
        requestId: request.id?.toString(),
        method: request.method,
        reason: RpcClientTokenConstants.missingClientTokenReason,
      );
      recordAuthSqlDenied(
        request,
        sql: investigationSqlOnDeny,
        explicitReason: RpcClientTokenConstants.missingClientTokenReason,
      );
      final rpcError = FailureToRpcErrorMapper.map(
        _support.buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final authorizedFingerprints = <String>{};
    for (final raw in sqlStatements) {
      final stmt = skipEmptyAfterTrim ? raw.trim() : raw;
      if (skipEmptyAfterTrim && stmt.isEmpty) {
        continue;
      }

      if (deduplicateEquivalentSql) {
        final fingerprint = sqlAuthorizationFingerprint(stmt);
        if (authorizedFingerprints.contains(fingerprint)) {
          continue;
        }
        authorizedFingerprints.add(fingerprint);
      }

      final authStopwatch = Stopwatch()..start();
      final authResult = await _support.authorizeWithBudget(
        token: clientToken,
        sql: stmt,
        requestDatabase: requestDatabase,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      authStopwatch.stop();
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final ctx = failure.context;
        _authMetrics?.recordDenied(
          requestId: request.id?.toString(),
          method: request.method,
          latencyMs: authStopwatch.elapsedMilliseconds,
          clientId: ctx['client_id'] as String?,
          operation: ctx['operation'] as String?,
          resource: ctx['resource'] as String?,
          reason: ctx['reason'] as String?,
        );
        recordAuthSqlDenied(
          request,
          sql: stmt,
          failure: failure,
        );
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
      _authMetrics?.recordAuthorized(
        requestId: request.id?.toString(),
        method: request.method,
        latencyMs: authStopwatch.elapsedMilliseconds,
      );
    }

    return null;
  }

  void recordAuthSqlDenied(
    RpcRequest request, {
    required String sql,
    domain.Failure? failure,
    String? explicitReason,
  }) {
    if (!_featureFlags.enableDashboardSqlInvestigationFeed) {
      return;
    }
    final collector = _sqlInvestigation;
    if (collector == null) {
      return;
    }
    if (!request.method.startsWith('sql.')) {
      return;
    }

    var reason = explicitReason;
    String? clientId;
    String? operation;
    String? resource;
    if (failure != null) {
      final ctx = failure.context;
      reason ??= ctx['reason'] as String?;
      clientId = ctx['client_id'] as String?;
      operation = ctx['operation'] as String?;
      resource = ctx['resource'] as String?;
    }

    collector.recordAuthorizationDenied(
      method: request.method,
      originalSql: sql,
      rpcRequestId: request.id?.toString(),
      reason: reason,
      clientId: clientId,
      operation: operation,
      resource: resource,
    );
  }

  void _logMissingClientTokenOnce(RpcRequest request) {
    if (_loggedMissingClientTokenThisSession) {
      return;
    }
    _loggedMissingClientTokenThisSession = true;
    developer.log(
      'Hub SQL RPC rejected: missing client_token (logged once per app session)',
      name: 'sql_rpc_method_handler',
      level: 900,
      error: <String, Object?>{
        'method': request.method,
        'request_id': request.id?.toString(),
        'reason': RpcClientTokenConstants.missingClientTokenReason,
      },
    );
  }
}
