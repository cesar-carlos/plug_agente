/// Minimal Hub agent login for E2E tooling (Dio only, no Flutter).
library;

import 'package:dio/dio.dart';

import 'hub_url_for_e2e.dart';

const int _httpOk = 200;
const String _authAgentLoginPath = '/api/v1/auth/agent-login';
const String _authAgentLoginCompatPath = '/auth/agent-login';
const String _authLoginPath = '/auth/login';

class HubLoginResult {
  const HubLoginResult({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

class HubLoginException implements Exception {
  HubLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<HubLoginResult> loginHubAgent({
  required String serverUrl,
  required String agentId,
  required String username,
  required String password,
  Dio? dio,
}) async {
  final client = dio ?? Dio();
  DioException? lastFallbackError;

  final attempts = <({String path, Map<String, dynamic> payload})>[
    (
      path: _authAgentLoginPath,
      payload: <String, dynamic>{
        'username': username,
        'password': password,
        'agentId': agentId,
      },
    ),
    (
      path: _authAgentLoginCompatPath,
      payload: <String, dynamic>{
        'username': username,
        'password': password,
        'agentId': agentId,
      },
    ),
    (
      path: _authLoginPath,
      payload: <String, dynamic>{
        'username': username,
        'password': password,
      },
    ),
  ];

  for (final attempt in attempts) {
    final url = joinServerUrlAndPath(serverUrl, attempt.path);
    try {
      final response = await client.post<Map<String, dynamic>>(
        url,
        data: attempt.payload,
      );
      if (response.statusCode == _httpOk) {
        return _parseAuthToken(response.data ?? const <String, dynamic>{});
      }
      throw HubLoginException('Login failed with status ${response.statusCode}');
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 404 || status == 405) {
        lastFallbackError = error;
        continue;
      }
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = _readString(data, 'error') ?? _readString(data, 'message');
        if (message != null && message.isNotEmpty) {
          throw HubLoginException(message);
        }
      }
      throw HubLoginException('Login request failed: ${error.message ?? error.type.name}');
    }
  }

  if (lastFallbackError != null) {
    throw HubLoginException(
      'No auth endpoint accepted login (${lastFallbackError.response?.statusCode ?? 'network error'})',
    );
  }
  throw HubLoginException('Login failed');
}

Future<HubLoginResult> refreshHubAgentSession({
  required String serverUrl,
  required String refreshToken,
  Dio? dio,
}) async {
  final client = dio ?? Dio();
  DioException? lastFallbackError;
  final attempts = <String>[
    '/api/v1/auth/refresh',
    '/auth/refresh',
  ];

  for (final path in attempts) {
    final url = joinServerUrlAndPath(serverUrl, path);
    try {
      final response = await client.post<Map<String, dynamic>>(
        url,
        data: <String, dynamic>{'refreshToken': refreshToken},
      );
      if (response.statusCode == _httpOk) {
        return _parseAuthToken(response.data ?? const <String, dynamic>{});
      }
      throw HubLoginException('Refresh failed with status ${response.statusCode}');
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 404 || status == 405) {
        lastFallbackError = error;
        continue;
      }
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = _readString(data, 'error') ?? _readString(data, 'message');
        if (message != null && message.isNotEmpty) {
          throw HubLoginException(message);
        }
      }
      throw HubLoginException('Refresh request failed: ${error.message ?? error.type.name}');
    }
  }

  if (lastFallbackError != null) {
    throw HubLoginException(
      'No refresh endpoint accepted request (${lastFallbackError.response?.statusCode ?? 'network error'})',
    );
  }
  throw HubLoginException('Refresh failed');
}

/// Parses Hub login JSON without performing HTTP (for tests and tooling).
HubLoginResult parseHubLoginResponse(Map<String, dynamic> data) => _parseAuthToken(data);

HubLoginResult _parseAuthToken(Map<String, dynamic> data) {
  final accessToken = _readString(data, 'accessToken') ?? _readString(data, 'token');
  final refreshToken = _readString(data, 'refreshToken');
  if (accessToken != null && accessToken.trim().isNotEmpty && refreshToken != null && refreshToken.trim().isNotEmpty) {
    return HubLoginResult(
      accessToken: accessToken.trim(),
      refreshToken: refreshToken.trim(),
    );
  }
  final error = _readString(data, 'error') ?? _readString(data, 'message') ?? 'Login failed';
  throw HubLoginException(error);
}

String? _readString(Map<String, dynamic> data, String key) {
  final value = data[key];
  return value is String ? value : null;
}
