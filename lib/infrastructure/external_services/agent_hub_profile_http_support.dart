import 'package:dio/dio.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_catalog_snapshot.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Shared HTTP helpers for hub agent profile REST calls.
abstract final class AgentHubProfileHttpSupport {
  static Map<String, dynamic>? readJsonMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return null;
  }

  static int? parseProfileVersion(Object? raw) {
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

  static String? parseProfileUpdatedAt(Map<String, dynamic> agent) {
    final updatedAt = agent['profileUpdatedAt'] ?? agent['profile_updated_at'];
    return updatedAt is String ? updatedAt : null;
  }

  static Result<void> validateCredentials({
    required String serverUrl,
    required String agentId,
    required String accessToken,
  }) {
    if (serverUrl.trim().isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }
    if (agentId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('Agent ID cannot be empty'));
    }
    if (accessToken.trim().isEmpty) {
      return Failure(domain.ValidationFailure('Access token is required'));
    }
    return const Success(unit);
  }

  static String profileUrl(String serverUrl, String agentId) {
    return joinServerUrlAndPath(
      hubHttpBaseUrl(serverUrl.trim()),
      AppConstants.agentHubProfilePath(agentId.trim()),
    );
  }

  static Map<String, dynamic> authHeaders(String accessToken) {
    return <String, dynamic>{'Authorization': 'Bearer ${accessToken.trim()}'};
  }

  static Result<AgentHubProfilePushResult> parsePushResult(
    Object? responseData, {
    required String operation,
  }) {
    final data = readJsonMap(responseData);
    if (data == null) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Hub returned an empty profile response',
          context: {'operation': operation},
        ),
      );
    }
    return parseAgentCatalog(data['agent'], operation: operation).map(
      (snapshot) => AgentHubProfilePushResult(
        profileVersion: snapshot.profileVersion,
        profileUpdatedAt: snapshot.profileUpdatedAt,
      ),
    );
  }

  static Result<AgentHubProfileCatalogSnapshot> parseAgentCatalog(
    Object? agentRaw, {
    required String operation,
  }) {
    final agent = readJsonMap(agentRaw);
    if (agent == null) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Hub response missing agent object',
          context: {'operation': operation},
        ),
      );
    }
    final parsedVersion = parseProfileVersion(
      agent['profileVersion'] ?? agent['profile_version'],
    );
    if (parsedVersion == null) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Hub response missing or invalid profileVersion',
          context: {'operation': operation},
        ),
      );
    }
    return Success(
      AgentHubProfileCatalogSnapshot(
        profileVersion: parsedVersion,
        profileUpdatedAt: parseProfileUpdatedAt(agent),
        agentPayload: agent,
      ),
    );
  }

  static String? parseErrorMessage(Object? body) {
    final data = readJsonMap(body);
    if (data == null) {
      return null;
    }
    final msg = data['message'];
    if (msg is String && msg.trim().isNotEmpty) {
      return msg.trim();
    }
    return null;
  }

  static domain.Failure failureForStatus(
    int? status,
    Object? body, {
    required String operation,
  }) {
    final messageFromBody = parseErrorMessage(body);
    final context = <String, dynamic>{
      'operation': operation,
      'statusCode': ?status,
    };
    switch (status) {
      case AppConstants.httpStatusUnauthorized:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Session expired or invalid. Sign in again.',
          context: context,
        );
      case AppConstants.httpStatusForbidden:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Not allowed to update this agent profile.',
          context: context,
        );
      case AppConstants.httpStatusConflict:
        return domain.ProfileVersionConflictFailure.withContext(
          message:
              messageFromBody ??
              'Profile was changed on the server. Reload from the server and try again.',
          context: context,
        );
      case AppConstants.httpStatusTooManyRequests:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Too many profile updates. Wait and try again.',
          context: context,
        );
      default:
        return domain.ServerFailure.withContext(
          message: messageFromBody ?? 'Hub rejected the profile update (HTTP $status).',
          context: context,
        );
    }
  }

  static void logHubResponse({
    required String operation,
    required Response<dynamic> response,
    String? agentId,
    bool success = true,
  }) {
    final requestId = response.headers.value('x-request-id') ??
        response.headers.value('X-Request-Id');
    final buffer = StringBuffer(
      'Hub $operation ${success ? 'succeeded' : 'failed'}: '
      'status=${response.statusCode}',
    );
    if (agentId != null && agentId.isNotEmpty) {
      buffer.write(', agentId=$agentId');
    }
    if (requestId != null && requestId.isNotEmpty) {
      buffer.write(', x-request-id=$requestId');
    }
    if (success) {
      AppLogger.info(buffer.toString());
    } else {
      AppLogger.warning(buffer.toString());
    }
  }

  static void logHubNetworkError({
    required String operation,
    required DioException error,
    String? agentId,
  }) {
    final status = error.response?.statusCode;
    final requestId = error.response?.headers.value('x-request-id');
    final buffer = StringBuffer('Hub $operation network error');
    if (status != null) {
      buffer.write(': status=$status');
    }
    if (agentId != null && agentId.isNotEmpty) {
      buffer.write(', agentId=$agentId');
    }
    if (requestId != null && requestId.isNotEmpty) {
      buffer.write(', x-request-id=$requestId');
    }
    AppLogger.warning(buffer.toString(), error);
  }
}
