import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_diagnostics_snapshot_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentMetadataRpcInvalidParams =
    RpcResponse Function(
      RpcRequest request,
      String detail, {
      String? rpcReason,
      Map<String, dynamic> extraFields,
    });

typedef AgentMetadataRpcInternalError =
    RpcResponse Function(
      RpcRequest request,
      String detail,
    );

typedef AgentMetadataRpcAuthorizeWithBudget =
    Future<Result<void>> Function({
      required String token,
      required String sql,
      required String? requestDatabase,
      required String? requestId,
      required String method,
      required DateTime? deadline,
    });

class AgentMetadataRpcMethodHandlerSupport {
  const AgentMetadataRpcMethodHandlerSupport({
    required this.invalidParams,
    required this.internalError,
    required this.buildMissingClientTokenFailure,
    required this.authorizeWithBudget,
  });

  final AgentMetadataRpcInvalidParams invalidParams;
  final AgentMetadataRpcInternalError internalError;
  final domain.ConfigurationFailure Function() buildMissingClientTokenFailure;
  final AgentMetadataRpcAuthorizeWithBudget authorizeWithBudget;
}

class AgentMetadataRpcMethodHandlerOperations {
  AgentMetadataRpcMethodHandlerOperations({
    required HealthService healthService,
    required GetClientTokenPolicy getClientTokenPolicy,
    required ClientTokenGetPolicyRateLimiter getPolicyRateLimiter,
    required FeatureFlags featureFlags,
    required AgentMetadataRpcMethodHandlerSupport support,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    IOdbcDiagnosticsSnapshotCollector? odbcNativeMetricsService,
    Duration authorizationStageBudget = _defaultAuthorizationStageBudget,
  }) : _healthService = healthService,
       _getClientTokenPolicy = getClientTokenPolicy,
       _getPolicyRateLimiter = getPolicyRateLimiter,
       _featureFlags = featureFlags,
       _support = support,
       _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _dispatchMetrics = dispatchMetrics,
       _odbcNativeMetricsService = odbcNativeMetricsService,
       _authorizationStageBudgetDuration = authorizationStageBudget;

  final HealthService _healthService;
  final GetClientTokenPolicy _getClientTokenPolicy;
  final ClientTokenGetPolicyRateLimiter _getPolicyRateLimiter;
  final FeatureFlags _featureFlags;
  final AgentMetadataRpcMethodHandlerSupport _support;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final IOdbcDiagnosticsSnapshotCollector? _odbcNativeMetricsService;
  final Duration _authorizationStageBudgetDuration;

  DateTime? _odbcDiagnosticsCacheExpiresAt;
  Map<String, dynamic>? _odbcDiagnosticsCache;

  static const _odbcDiagnosticsCacheTtl = Duration(seconds: 10);
  static const _defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const _agentProfileAuthorizationSql = 'SELECT * FROM agent_profile';

  Future<RpcResponse> handleAgentGetProfile(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    // Params structure and allowed keys are validated upstream by
    // RpcRequestSchemaValidator before dispatch reaches this method.

    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudgetDuration)
        : null;

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authResult = await _support.authorizeWithBudget(
        token: clientToken,
        sql: _agentProfileAuthorizationSql,
        requestDatabase: null,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
    }

    final resolver = _activeConfigResolver;
    final repository = _configRepository;
    if (resolver == null && repository == null) {
      return _support.internalError(
        request,
        'Agent profile repository is not available',
      );
    }

    final result = resolver != null
        ? await resolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await repository!.getCurrentConfigMetadata();
    if (result.isError()) {
      final failure = result.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final config = result.getOrThrow();
    final profileResult = AgentProfile.fromConfig(config);
    if (profileResult.isError()) {
      final failure = profileResult.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final profile = profileResult.getOrThrow();
    final profileUpdatedAt = _resolveAgentProfileUpdatedAt(config);
    final includeDiagnostics = _readBoolParam(
      request.params,
      'include_diagnostics',
      defaultValue: false,
    );
    final payload = <String, dynamic>{
      'agent_id': agentId,
      'profile': profile.toJson(),
      if (config.hubProfileVersion != null) 'profile_version': config.hubProfileVersion,
      'updated_at': profileUpdatedAt,
      if (includeDiagnostics) 'odbc': await _collectOdbcDiagnosticsPayload(),
    };
    return RpcResponse.success(
      id: request.id,
      result: payload,
    );
  }

  Future<RpcResponse> handleAgentGetHealth(
    RpcRequest request,
    String? clientToken,
  ) async {
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudgetDuration)
        : null;

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      final rpcError = FailureToRpcErrorMapper.map(
        _support.buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authResult = await _support.authorizeWithBudget(
        token: clientToken,
        sql: _agentProfileAuthorizationSql,
        requestDatabase: null,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
    }

    final raw = await _healthService.getHealthStatusAsync();
    final result = json.decode(json.encode(raw)) as Map<String, dynamic>;
    return RpcResponse.success(
      id: request.id,
      result: result,
    );
  }

  Future<RpcResponse> handleClientTokenGetPolicy(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return _support.invalidParams(
        request,
        'client_token.getPolicy requires enableClientTokenAuthorization',
        rpcReason: 'client_token_authorization_disabled',
      );
    }

    if (!_featureFlags.enableClientTokenPolicyIntrospection) {
      return _support.invalidParams(
        request,
        'client_token.getPolicy requires enableClientTokenPolicyIntrospection',
        rpcReason: 'client_token_introspection_disabled',
      );
    }

    if (clientToken == null || clientToken.isEmpty) {
      final rpcError = FailureToRpcErrorMapper.map(
        _support.buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final scopeKey = '$agentId:${hashClientCredentialToken(clientToken)}';
    if (!_getPolicyRateLimiter.tryAcquire(scopeKey)) {
      _dispatchMetrics?.recordClientTokenGetPolicyRateLimited();
      return _clientTokenGetPolicyRateLimited(request);
    }

    final policyResult = await _getClientTokenPolicy.call(clientToken);
    return policyResult.fold(
      (ClientTokenPolicy policy) {
        _dispatchMetrics?.recordClientTokenGetPolicySuccess();
        return RpcResponse.success(
          id: request.id,
          result: policy.toRpcResultJson(),
        );
      },
      (Object failure) {
        final domainFailure = failure is domain.Failure
            ? failure
            : domain.ServerFailure.withContext(
                message: 'Unexpected error while resolving client token policy',
                context: {'unexpected_type': failure.runtimeType.toString()},
              );
        _dispatchMetrics?.recordClientTokenGetPolicyFailure(domainFailure);
        if (failure is! domain.Failure) {
          developer.log(
            'client_token.getPolicy unexpected failure type',
            name: 'rpc_method_dispatcher',
            level: 500,
            error: failure is Exception ? failure : null,
          );
        }
        final rpcError = FailureToRpcErrorMapper.map(
          domainFailure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  String _resolveAgentProfileUpdatedAt(Config config) {
    if (config.hubProfileVersion != null) {
      final hubUpdatedAt = _normalizeIsoDateTime(config.hubProfileUpdatedAt);
      if (hubUpdatedAt != null) {
        return hubUpdatedAt;
      }
    }
    return config.updatedAt.toUtc().toIso8601String();
  }

  String? _normalizeIsoDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value.trim());
    return parsed?.toUtc().toIso8601String();
  }

  RpcResponse _clientTokenGetPolicyRateLimited(RpcRequest request) {
    const code = RpcErrorCode.rateLimited;
    final window = _clientTokenGetPolicyRateLimitWindowFields();
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'client_token.getPolicy rate limit exceeded for this agent and credential',
          correlationId: request.id?.toString(),
          reason: RpcClientTokenConstants.clientTokenGetPolicyRateLimitedReason,
          extra: {
            'method': request.method,
            'retry_after_ms': window['retry_after_ms'],
            'reset_at': window['reset_at'],
          },
        ),
      ),
    );
  }

  /// Next UTC minute boundary for the fixed window used by the getPolicy rate limiter.
  Map<String, dynamic> _clientTokenGetPolicyRateLimitWindowFields() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    final windowEndMs = ((ms ~/ 60000) + 1) * 60000;
    final retryAfterMs = windowEndMs - ms;
    final resetAt = DateTime.fromMillisecondsSinceEpoch(windowEndMs, isUtc: true).toIso8601String();
    return <String, dynamic>{
      'retry_after_ms': retryAfterMs,
      'reset_at': resetAt,
    };
  }

  Future<Map<String, dynamic>> _collectOdbcDiagnosticsPayload() async {
    final metricsService = _odbcNativeMetricsService;
    if (metricsService == null) {
      return const <String, dynamic>{'available': false};
    }

    final now = DateTime.now().toUtc();
    final cached = _odbcDiagnosticsCache;
    final expiresAt = _odbcDiagnosticsCacheExpiresAt;
    if (cached != null && expiresAt != null && now.isBefore(expiresAt)) {
      return cached;
    }

    final snapshotResult = await metricsService.collectSnapshot();
    final payload = snapshotResult.fold(
      (snapshot) => <String, dynamic>{
        'available': true,
        'snapshot': snapshot,
      },
      (failure) => <String, dynamic>{
        'available': false,
        'error': failure.toString(),
      },
    );
    _odbcDiagnosticsCache = payload;
    _odbcDiagnosticsCacheExpiresAt = now.add(_odbcDiagnosticsCacheTtl);
    return payload;
  }

  bool _readBoolParam(
    dynamic params,
    String key, {
    required bool defaultValue,
  }) {
    if (params is! Map<String, dynamic>) {
      return defaultValue;
    }
    final value = params[key];
    return value is bool ? value : defaultValue;
  }
}
