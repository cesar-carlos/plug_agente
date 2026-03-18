import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/infrastructure/errors/failure_converter.dart';
import 'package:result_dart/result_dart.dart';

class AuthClient implements IAuthClient {
  AuthClient(this._dio);
  final Dio _dio;

  String _normalizeUrl(String baseUrl, String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$normalizedBase$path';
  }

  @override
  Future<Result<AuthToken>> login(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    DioException? lastFallbackError;
    try {
      final endpointAttempts = [
        (
          path: AppConstants.authAgentLoginPath,
          payload: <String, dynamic>{
            'username': credentials.username,
            'password': credentials.password,
            'agentId': credentials.agentId,
          },
        ),
        (
          path: AppConstants.authAgentLoginCompatPath,
          payload: <String, dynamic>{
            'username': credentials.username,
            'password': credentials.password,
            'agentId': credentials.agentId,
          },
        ),
        (
          path: AppConstants.authLoginPath,
          payload: <String, dynamic>{
            'username': credentials.username,
            'password': credentials.password,
          },
        ),
      ];

      for (final attempt in endpointAttempts) {
        final url = _normalizeUrl(serverUrl, attempt.path);
        debugPrint(
          'AuthClient: Attempting login to $url with username: ${credentials.username}',
        );
        try {
          final response = await _dio.post<Map<String, dynamic>>(
            url,
            data: attempt.payload,
          );

          debugPrint('AuthClient: Response status: ${response.statusCode}');

          if (response.statusCode == AppConstants.httpStatusOk) {
            final data = response.data ?? const <String, dynamic>{};
            final parsed = _parseAuthToken(
              data,
              fallbackErrorMessage: 'Login failed',
            );
            if (parsed.isSuccess()) {
              return parsed;
            }
            return Failure(parsed.exceptionOrNull()! as domain.Failure);
          }

          return Failure(
            domain.ServerFailure('Server error: ${response.statusCode}'),
          );
        } on DioException catch (e) {
          if (_shouldTryNextEndpoint(e)) {
            lastFallbackError = e;
            continue;
          }
          rethrow;
        }
      }

      if (lastFallbackError != null) {
        throw lastFallbackError;
      }

      return Failure(domain.ValidationFailure('Login failed'));
    } on DioException catch (e, stackTrace) {
      debugPrint(
        'AuthClient: DioException: ${e.message}, Type: ${e.type}, Response: ${e.response?.statusCode}',
      );
      if (e.response?.statusCode == AppConstants.httpStatusUnauthorized) {
        final data = e.response?.data as Map<String, dynamic>?;
        return Failure(
          domain.ValidationFailure(
            data?['error'] as String? ?? 'Invalid credentials',
          ),
        );
      }
      return Failure(
        FailureConverter.convert(
          e,
          stackTrace,
          operation: 'login',
          additionalContext: {
            'serverUrl': serverUrl,
            'exceptionType': e.type.toString(),
          },
        ),
      );
    } on Exception catch (e, stackTrace) {
      debugPrint('AuthClient: Unexpected error: $e');
      return Failure(
        FailureConverter.convert(
          e,
          stackTrace,
          operation: 'login',
          additionalContext: {'serverUrl': serverUrl},
        ),
      );
    }
  }

  @override
  Future<Result<AuthToken>> refreshToken(
    String serverUrl,
    String refreshToken,
  ) async {
    DioException? lastFallbackError;
    try {
      final endpointAttempts = [
        AppConstants.authRefreshPath,
        AppConstants.authRefreshCompatPath,
      ];

      for (final endpoint in endpointAttempts) {
        final url = _normalizeUrl(serverUrl, endpoint);
        try {
          final response = await _dio.post<Map<String, dynamic>>(
            url,
            data: {'refreshToken': refreshToken},
          );

          if (response.statusCode == AppConstants.httpStatusOk) {
            final data = response.data ?? const <String, dynamic>{};
            final parsed = _parseAuthToken(
              data,
              fallbackErrorMessage: 'Refresh failed',
            );
            if (parsed.isSuccess()) {
              return parsed;
            }
            return Failure(parsed.exceptionOrNull()! as domain.Failure);
          }

          return Failure(
            domain.ServerFailure('Server error: ${response.statusCode}'),
          );
        } on DioException catch (e) {
          if (_shouldTryNextEndpoint(e)) {
            lastFallbackError = e;
            continue;
          }
          rethrow;
        }
      }

      if (lastFallbackError != null) {
        throw lastFallbackError;
      }

      return Failure(domain.ValidationFailure('Refresh failed'));
    } on DioException catch (e, stackTrace) {
      if (e.response?.statusCode == AppConstants.httpStatusUnauthorized) {
        final data = e.response?.data as Map<String, dynamic>?;
        return Failure(
          domain.ValidationFailure(
            data?['error'] as String? ?? 'Refresh token expired or revoked',
          ),
        );
      }
      return Failure(
        FailureConverter.convert(
          e,
          stackTrace,
          operation: 'refreshToken',
          additionalContext: {
            'serverUrl': serverUrl,
            'exceptionType': e.type.toString(),
          },
        ),
      );
    } on Exception catch (e, stackTrace) {
      return Failure(
        FailureConverter.convert(
          e,
          stackTrace,
          operation: 'refreshToken',
          additionalContext: {'serverUrl': serverUrl},
        ),
      );
    }
  }

  bool _shouldTryNextEndpoint(DioException error) {
    final statusCode = error.response?.statusCode;
    return statusCode == 404 || statusCode == 405;
  }

  Result<AuthToken> _parseAuthToken(
    Map<String, dynamic> data, {
    required String fallbackErrorMessage,
  }) {
    final accessToken = _readString(data, 'accessToken') ?? _readString(data, 'token');
    final refreshToken = _readString(data, 'refreshToken');

    if (accessToken != null &&
        accessToken.trim().isNotEmpty &&
        refreshToken != null &&
        refreshToken.trim().isNotEmpty) {
      return Success(
        AuthToken(
          token: accessToken,
          refreshToken: refreshToken,
        ),
      );
    }

    return Failure(
      domain.ValidationFailure(
        _readString(data, 'error') ?? _readString(data, 'message') ?? fallbackErrorMessage,
      ),
    );
  }

  String? _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value : null;
  }
}
