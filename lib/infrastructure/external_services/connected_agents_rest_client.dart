import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// REST client for hub agent listing used during backup restore (duplicate-session probe).
///
/// Uses a short Dio timeout from dependency registration and per-request caps
/// from ConnectionConstants.backupRestoreAgentsListTimeout.
class ConnectedAgentsRestClient implements IConnectedAgentsGateway {
  ConnectedAgentsRestClient(this._dio);

  final Dio _dio;

  @override
  Future<Result<String>> fetchAgentsList({
    required String serverUrl,
    required String accessToken,
  }) async {
    final trimmedUrl = serverUrl.trim();
    final token = accessToken.trim();
    if (trimmedUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }
    if (token.isEmpty) {
      return Failure(domain.ValidationFailure('Access token is required'));
    }

    final url = joinServerUrlAndPath(trimmedUrl, AppConstants.agentsListPath);
    try {
      final response = await _dio
          .get<dynamic>(
            url,
            options: Options(
              headers: <String, dynamic>{
                'Authorization': 'Bearer $token',
              },
              receiveTimeout: ConnectionConstants.backupRestoreAgentsListTimeout,
              sendTimeout: ConnectionConstants.backupRestoreAgentsListTimeout,
            ),
          )
          .timeout(ConnectionConstants.backupRestoreAgentsListTimeout);

      if (response.statusCode == AppConstants.httpStatusOk && response.data != null) {
        final body = switch (response.data) {
          final String s => s,
          final Map<String, dynamic> m => jsonEncode(m),
          final List<dynamic> l => jsonEncode(l),
          _ => jsonEncode(response.data),
        };
        return Success(body);
      }

      return Failure(
        domain.ServerFailure.withContext(
          message: 'Could not load agent list from hub',
          context: {'statusCode': response.statusCode},
        ),
      );
    } on TimeoutException catch (e, stackTrace) {
      developer.log(
        'connected_agents fetch timed out',
        name: 'connected_agents_rest_client',
        error: e,
        stackTrace: stackTrace,
      );
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Hub agent list request timed out',
          cause: e,
          context: const {'operation': 'fetchAgentsList'},
        ),
      );
    } on DioException catch (e, stackTrace) {
      developer.log(
        'connected_agents fetch failed',
        name: 'connected_agents_rest_client',
        error: e,
        stackTrace: stackTrace,
      );
      final status = e.response?.statusCode;
      if (status == AppConstants.httpStatusUnauthorized) {
        return Failure(
          domain.ServerFailure.withContext(
            message: 'Session expired or invalid for agent list',
            context: const {'operation': 'fetchAgentsList'},
          ),
        );
      }
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Could not reach the hub to verify agent sessions',
          cause: e,
          context: const {'operation': 'fetchAgentsList'},
        ),
      );
    }
  }
}
