import 'package:dio/dio.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:result_dart/result_dart.dart';

class AgentHubProfileRestClient implements IAgentHubProfileGateway {
  AgentHubProfileRestClient(this._dio);

  final Dio _dio;

  @override
  Future<Result<AgentHubProfilePushResult>> patchProfile({
    required String serverUrl,
    required String agentId,
    required String accessToken,
    required Map<String, dynamic> body,
    String? idempotencyKey,
  }) async {
    final trimmedUrl = serverUrl.trim();
    final trimmedId = agentId.trim();
    final trimmedToken = accessToken.trim();
    if (trimmedUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }
    if (trimmedId.isEmpty) {
      return Failure(domain.ValidationFailure('Agent ID cannot be empty'));
    }
    if (trimmedToken.isEmpty) {
      return Failure(domain.ValidationFailure('Access token is required'));
    }

    final url = joinServerUrlAndPath(trimmedUrl, AppConstants.agentHubProfilePath(trimmedId));

    final headers = <String, dynamic>{
      'Authorization': 'Bearer $trimmedToken',
    };
    final trimmedIdem = idempotencyKey?.trim();
    if (trimmedIdem != null && trimmedIdem.isNotEmpty) {
      headers['Idempotency-Key'] = trimmedIdem;
    }

    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        url,
        data: body,
        options: Options(headers: headers),
      );

      if (response.statusCode == AppConstants.httpStatusOk) {
        final data = response.data;
        if (data == null) {
          return Failure(
            domain.ServerFailure.withContext(
              message: 'Hub returned an empty profile response',
              context: const {'operation': 'patchAgentProfile'},
            ),
          );
        }
        final agent = data['agent'];
        if (agent is! Map<String, dynamic>) {
          return Failure(
            domain.ServerFailure.withContext(
              message: 'Hub response missing agent object',
              context: const {'operation': 'patchAgentProfile'},
            ),
          );
        }
        final parsedVersion = _parseProfileVersion(agent['profileVersion']);
        if (parsedVersion == null) {
          return Failure(
            domain.ServerFailure.withContext(
              message: 'Hub response missing or invalid profileVersion',
              context: const {'operation': 'patchAgentProfile'},
            ),
          );
        }
        final updatedAt = agent['profileUpdatedAt'];
        return Success(
          AgentHubProfilePushResult(
            profileVersion: parsedVersion,
            profileUpdatedAt: updatedAt is String ? updatedAt : null,
          ),
        );
      }

      return Failure(_failureForStatus(response.statusCode, response.data));
    } on DioException catch (error, stackTrace) {
      final status = error.response?.statusCode;
      if (status != null) {
        return Failure(_failureForStatus(status, error.response?.data));
      }
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Could not reach the hub to update profile',
          cause: error,
          context: {
            'operation': 'patchAgentProfile',
            'stackTrace': stackTrace.toString(),
          },
        ),
      );
    }
  }

  static int? _parseProfileVersion(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  domain.Failure _failureForStatus(int? status, Object? body) {
    final messageFromBody = _parseErrorMessage(body);
    switch (status) {
      case AppConstants.httpStatusUnauthorized:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Session expired or invalid. Sign in again.',
          context: {'operation': 'patchAgentProfile', 'statusCode': status},
        );
      case AppConstants.httpStatusForbidden:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Not allowed to update this agent profile.',
          context: {'operation': 'patchAgentProfile', 'statusCode': status},
        );
      case AppConstants.httpStatusConflict:
        return domain.ServerFailure.withContext(
          message:
              messageFromBody ??
              'Profile was changed on the server. Reload and try again, or retry after resolving the conflict.',
          context: {'operation': 'patchAgentProfile', 'statusCode': status},
        );
      case AppConstants.httpStatusTooManyRequests:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Too many profile updates. Wait and try again.',
          context: {'operation': 'patchAgentProfile', 'statusCode': status},
        );
      default:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Hub rejected the profile update (HTTP $status).',
          context: {'operation': 'patchAgentProfile', 'statusCode': status},
        );
    }
  }

  String? _parseErrorMessage(Object? body) {
    if (body is Map<String, dynamic>) {
      final msg = body['message'];
      if (msg is String && msg.trim().isNotEmpty) {
        return msg.trim();
      }
    }
    return null;
  }
}
