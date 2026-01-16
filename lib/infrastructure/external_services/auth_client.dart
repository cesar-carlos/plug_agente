import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/auth_token.dart';
import '../../domain/errors/failures.dart' as domain;
import '../../domain/repositories/i_auth_client.dart';
import '../../domain/value_objects/auth_credentials.dart';

class AuthClient implements IAuthClient {
  final Dio _dio;

  AuthClient(this._dio);

  String _normalizeUrl(String baseUrl, String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$normalizedBase$path';
  }

  String _getErrorMessage(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;

      if (data is Map<String, dynamic> && data['error'] != null) {
        return data['error'] as String;
      }

      return 'Server error: $statusCode';
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.badResponse:
        return 'Invalid server response';
      case DioExceptionType.cancel:
        return 'Request was cancelled';
      case DioExceptionType.connectionError:
        return 'Unable to connect to server. Please check the server URL and your internet connection.';
      case DioExceptionType.badCertificate:
        return 'SSL certificate error';
      case DioExceptionType.unknown:
        return e.message ?? 'Network error occurred';
    }
  }

  @override
  Future<Result<AuthToken>> login(String serverUrl, AuthCredentials credentials) async {
    try {
      final url = _normalizeUrl(serverUrl, AppConstants.authLoginPath);
      debugPrint('AuthClient: Attempting login to $url with username: ${credentials.username}');

      final response = await _dio.post(url, data: {'username': credentials.username, 'password': credentials.password});

      debugPrint('AuthClient: Response status: ${response.statusCode}');

      if (response.statusCode == AppConstants.httpStatusOk) {
        final data = response.data as Map<String, dynamic>;

        if (data['success'] == true) {
          final token = data['token'] as String;
          final refreshToken = data['refreshToken'] as String;

          return Success(AuthToken(token: token, refreshToken: refreshToken));
        }

        return Failure(domain.ValidationFailure(data['error'] as String? ?? 'Login failed'));
      }

      return Failure(domain.ServerFailure('Server error: ${response.statusCode}'));
    } on DioException catch (e) {
      debugPrint('AuthClient: DioException: ${e.message}, Type: ${e.type}, Response: ${e.response?.statusCode}');
      if (e.response?.statusCode == AppConstants.httpStatusUnauthorized) {
        final data = e.response?.data as Map<String, dynamic>?;
        return Failure(domain.ValidationFailure(data?['error'] as String? ?? 'Invalid credentials'));
      }
      return Failure(domain.NetworkFailure(_getErrorMessage(e)));
    } catch (e) {
      debugPrint('AuthClient: Unexpected error: $e');
      return Failure(domain.ServerFailure('Unexpected error: $e'));
    }
  }

  @override
  Future<Result<AuthToken>> refreshToken(String serverUrl, String refreshToken) async {
    try {
      final url = _normalizeUrl(serverUrl, AppConstants.authRefreshPath);
      final response = await _dio.post(url, data: {'refreshToken': refreshToken});

      if (response.statusCode == AppConstants.httpStatusOk) {
        final data = response.data as Map<String, dynamic>;

        if (data['success'] == true) {
          final token = data['token'] as String;
          final newRefreshToken = data['refreshToken'] as String;

          return Success(AuthToken(token: token, refreshToken: newRefreshToken));
        }

        return Failure(domain.ValidationFailure(data['error'] as String? ?? 'Refresh failed'));
      }

      return Failure(domain.ServerFailure('Server error: ${response.statusCode}'));
    } on DioException catch (e) {
      if (e.response?.statusCode == AppConstants.httpStatusUnauthorized) {
        final data = e.response?.data as Map<String, dynamic>?;
        return Failure(domain.ValidationFailure(data?['error'] as String? ?? 'Refresh token expired or revoked'));
      }
      return Failure(domain.NetworkFailure(_getErrorMessage(e)));
    } catch (e) {
      return Failure(domain.ServerFailure('Unexpected error: $e'));
    }
  }
}
