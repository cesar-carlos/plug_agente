import 'package:dio/dio.dart';
import 'package:plug_agente/application/ports/i_hub_access_token_renewer.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_catalog_snapshot.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/agent_hub_profile_http_support.dart';
import 'package:plug_agente/infrastructure/external_services/hub_http_auth_retry.dart';
import 'package:result_dart/result_dart.dart';

class AgentHubProfileRestClient implements IAgentHubProfileGateway {
  AgentHubProfileRestClient(
    this._dio, {
    IHubAccessTokenRenewer? accessTokenRenewer,
  }) : _accessTokenRenewer = accessTokenRenewer;

  final Dio _dio;
  final IHubAccessTokenRenewer? _accessTokenRenewer;

  static const String _patchOperation = 'patchAgentProfile';
  static const String _fetchOperation = 'fetchAgentProfile';

  @override
  Future<Result<AgentHubProfilePushResult>> patchProfile({
    required String serverUrl,
    required String agentId,
    required String accessToken,
    required Map<String, dynamic> body,
    String? idempotencyKey,
    String? configId,
  }) async {
    final validation = AgentHubProfileHttpSupport.validateCredentials(
      serverUrl: serverUrl,
      agentId: agentId,
      accessToken: accessToken,
    );
    if (validation.isError()) {
      return Failure(validation.exceptionOrNull()!);
    }

    final url = AgentHubProfileHttpSupport.profileUrl(serverUrl, agentId);
    final trimmedIdem = idempotencyKey?.trim();

    return HubHttpAuthRetry.execute(
      serverUrl: serverUrl,
      accessToken: accessToken,
      configId: configId,
      accessTokenRenewer: _accessTokenRenewer,
      request: (resolvedAccessToken) => _patchProfileOnce(
        url: url,
        body: body,
        headers: AgentHubProfileHttpSupport.authHeaders(resolvedAccessToken)
          ..addAll(
            trimmedIdem != null && trimmedIdem.isNotEmpty
                ? <String, dynamic>{'Idempotency-Key': trimmedIdem}
                : const <String, dynamic>{},
          ),
        agentId: agentId,
      ),
    );
  }

  Future<Result<AgentHubProfilePushResult>> _patchProfileOnce({
    required String url,
    required Map<String, dynamic> body,
    required Map<String, dynamic> headers,
    required String agentId,
  }) async {
    try {
      final response = await _dio.patch<dynamic>(
        url,
        data: body,
        options: Options(headers: headers),
      );

      if (response.statusCode == AppConstants.httpStatusOk) {
        AgentHubProfileHttpSupport.logHubResponse(
          operation: _patchOperation,
          response: response,
          agentId: agentId,
        );
        return AgentHubProfileHttpSupport.parsePushResult(
          response.data,
          operation: _patchOperation,
        );
      }

      AgentHubProfileHttpSupport.logHubResponse(
        operation: _patchOperation,
        response: response,
        agentId: agentId,
        success: false,
      );
      return Failure(
        AgentHubProfileHttpSupport.failureForStatus(
          response.statusCode,
          response.data,
          operation: _patchOperation,
        ),
      );
    } on DioException catch (error) {
      return Failure(_mapDioError(error, operation: _patchOperation, agentId: agentId));
    }
  }

  @override
  Future<Result<AgentHubProfileCatalogSnapshot>> fetchProfileCatalog({
    required String serverUrl,
    required String agentId,
    required String accessToken,
    String? configId,
  }) async {
    final validation = AgentHubProfileHttpSupport.validateCredentials(
      serverUrl: serverUrl,
      agentId: agentId,
      accessToken: accessToken,
    );
    if (validation.isError()) {
      return Failure(validation.exceptionOrNull()!);
    }

    final url = AgentHubProfileHttpSupport.profileUrl(serverUrl, agentId);

    return HubHttpAuthRetry.execute(
      serverUrl: serverUrl,
      accessToken: accessToken,
      configId: configId,
      accessTokenRenewer: _accessTokenRenewer,
      request: (resolvedAccessToken) => _fetchProfileCatalogOnce(
        url: url,
        accessToken: resolvedAccessToken,
        agentId: agentId,
      ),
    );
  }

  Future<Result<AgentHubProfileCatalogSnapshot>> _fetchProfileCatalogOnce({
    required String url,
    required String accessToken,
    required String agentId,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: AgentHubProfileHttpSupport.authHeaders(accessToken),
        ),
      );

      if (response.statusCode == AppConstants.httpStatusOk) {
        AgentHubProfileHttpSupport.logHubResponse(
          operation: _fetchOperation,
          response: response,
          agentId: agentId,
        );
        final data = AgentHubProfileHttpSupport.readJsonMap(response.data);
        if (data == null) {
          return Failure(
            domain.ServerFailure.withContext(
              message: 'Hub returned an empty profile response',
              context: const {'operation': _fetchOperation},
            ),
          );
        }
        return AgentHubProfileHttpSupport.parseAgentCatalog(
          data['agent'],
          operation: _fetchOperation,
        );
      }

      AgentHubProfileHttpSupport.logHubResponse(
        operation: _fetchOperation,
        response: response,
        agentId: agentId,
        success: false,
      );
      return Failure(
        AgentHubProfileHttpSupport.failureForStatus(
          response.statusCode,
          response.data,
          operation: _fetchOperation,
        ),
      );
    } on DioException catch (error) {
      return Failure(_mapDioError(error, operation: _fetchOperation, agentId: agentId));
    }
  }

  domain.Failure _mapDioError(
    DioException error, {
    required String operation,
    required String agentId,
  }) {
    AgentHubProfileHttpSupport.logHubNetworkError(
      operation: operation,
      error: error,
      agentId: agentId,
    );
    final status = error.response?.statusCode;
    if (status != null) {
      return AgentHubProfileHttpSupport.failureForStatus(
        status,
        error.response?.data,
        operation: operation,
      );
    }
    final message = operation == _fetchOperation
        ? 'Could not reach the hub to load profile'
        : 'Could not reach the hub to update profile';
    return domain.NetworkFailure.withContext(
      message: message,
      cause: error,
      context: {'operation': operation},
    );
  }
}
