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
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$normalizedBase$path';
  }

  @override
  Future<Result<AuthToken>> login(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    try {
      final url = _normalizeUrl(serverUrl, AppConstants.authLoginPath);
      debugPrint(
        'AuthClient: Attempting login to $url with username: ${credentials.username}',
      );

      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'username': credentials.username,
          'password': credentials.password,
        },
      );

      debugPrint('AuthClient: Response status: ${response.statusCode}');

      if (response.statusCode == AppConstants.httpStatusOk) {
        final data = response.data!;

        if (data['success'] == true) {
          final token = data['token'] as String;
          final refreshToken = data['refreshToken'] as String;

          return Success(AuthToken(token: token, refreshToken: refreshToken));
        }

        return Failure(
          domain.ValidationFailure(data['error'] as String? ?? 'Login failed'),
        );
      }

      return Failure(
        domain.ServerFailure('Server error: ${response.statusCode}'),
      );
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
    try {
      final url = _normalizeUrl(serverUrl, AppConstants.authRefreshPath);
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == AppConstants.httpStatusOk) {
        final data = response.data!;

        if (data['success'] == true) {
          final token = data['token'] as String;
          final newRefreshToken = data['refreshToken'] as String;

          return Success(
            AuthToken(token: token, refreshToken: newRefreshToken),
          );
        }

        return Failure(
          domain.ValidationFailure(
            data['error'] as String? ?? 'Refresh failed',
          ),
        );
      }

      return Failure(
        domain.ServerFailure('Server error: ${response.statusCode}'),
      );
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
}
