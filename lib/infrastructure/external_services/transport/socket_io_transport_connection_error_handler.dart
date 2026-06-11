import 'dart:async';
import 'dart:convert';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/hub_connect_error_auth_heuristics.dart';
import 'package:result_dart/result_dart.dart';

/// Structured `connect_error` payload emitted by hubs that follow the contract
/// `{ "code": "auth_failed", "reason": "...", "message": "..." }`.
final class StructuredConnectError {
  const StructuredConnectError({this.code, this.reason, this.message});

  factory StructuredConnectError.fromMap(Map<String, dynamic> map) {
    return StructuredConnectError(
      code: map['code']?.toString(),
      reason: map['reason']?.toString(),
      message: map['message']?.toString() ?? map['detail']?.toString(),
    );
  }

  final String? code;
  final String? reason;
  final String? message;

  bool get isAuthRelated {
    if (isHubConnectAuthRelatedStructured(code: code, reason: reason)) {
      return true;
    }
    final msg = message;
    if (msg == null || msg.trim().isEmpty) {
      return false;
    }
    return isHubConnectAuthRelatedMessage(msg);
  }
}

/// Maps Socket.IO connect/socket errors into typed failures and auth callbacks.
final class SocketIoTransportConnectionErrorHandler {
  SocketIoTransportConnectionErrorHandler({
    required String Function() resilienceLogPrefix,
    required String? Function() recoveryId,
    required void Function() closeSocket,
    required void Function()? onTokenExpired,
  }) : _resilienceLogPrefix = resilienceLogPrefix,
       _recoveryId = recoveryId,
       _closeSocket = closeSocket,
       _onTokenExpired = onTokenExpired;

  final String Function() _resilienceLogPrefix;
  final String? Function() _recoveryId;
  final void Function() _closeSocket;
  final void Function()? _onTokenExpired;

  void handleConnectionError(
    dynamic error,
    Completer<Result<void>> completer,
  ) {
    final structured = parseStructuredErrorPayload(error);
    final errorMessage = structured?.message ?? error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = buildConnectionFailure(
      errorMessage,
      errorObj,
      structured: structured,
    );
    AppLogger.error(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=connect_error ${failure.message}',
      failure.toTechnicalMessage(),
    );

    if (!completer.isCompleted) {
      _closeSocket();
    }

    if (isAuthRelated(structured, errorMessage)) {
      _onTokenExpired?.call();
    }

    if (completer.isCompleted) {
      return;
    }

    completer.complete(Failure(failure));
  }

  void handleSocketError(dynamic error) {
    final structured = parseStructuredErrorPayload(error);
    final errorMessage = structured?.message ?? error.toString();
    final errorObj = error as Object? ?? Exception(errorMessage);
    final failure = buildConnectionFailure(
      errorMessage,
      errorObj,
      structured: structured,
    );
    AppLogger.error(
      'resilience: ${_resilienceLogPrefix()}socket_transport event=socket_error ${failure.message}',
      failure.toTechnicalMessage(),
    );

    if (isAuthRelated(structured, errorMessage)) {
      _onTokenExpired?.call();
    }
  }

  static StructuredConnectError? parseStructuredErrorPayload(dynamic error) {
    if (error is Map<String, dynamic>) {
      return StructuredConnectError.fromMap(error);
    }
    if (error is Map) {
      return StructuredConnectError.fromMap({
        for (final entry in error.entries) entry.key.toString(): entry.value,
      });
    }
    if (error is String) {
      final trimmed = error.trim();
      if (trimmed.isEmpty || (trimmed[0] != '{' && trimmed[0] != '[')) {
        return null;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return StructuredConnectError.fromMap(decoded);
        }
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static bool isAuthRelated(StructuredConnectError? structured, String errorMessage) {
    if (structured != null && structured.isAuthRelated) {
      return true;
    }
    return isHubConnectAuthRelatedMessage(errorMessage);
  }

  domain.Failure buildConnectionFailure(
    String errorMessage,
    Object error, {
    StructuredConnectError? structured,
    Map<String, Object>? extraContext,
  }) {
    final context = connectFailureContext(
      structured: structured,
      extraContext: extraContext,
    );

    if (isHubConnectAuthRelatedMessage(errorMessage)) {
      return domain.ConfigurationFailure.withContext(
        message: 'Authentication failed. Please sign in again.',
        cause: error,
        context: context,
      );
    }

    return domain.NetworkFailure.withContext(
      message: 'Unable to connect to the hub. Check the server URL and your network connection.',
      cause: error,
      context: context,
    );
  }

  Map<String, Object> connectFailureContext({
    StructuredConnectError? structured,
    Map<String, Object>? extraContext,
  }) {
    final context = <String, Object>{
      'operation': 'connect',
      ...?extraContext,
    };
    final code = structured?.code;
    if (code != null && code.isNotEmpty) {
      context['hub_code'] = code;
    }
    final reason = structured?.reason;
    if (reason != null && reason.isNotEmpty) {
      context['hub_reason'] = reason;
    }
    final recoveryId = _recoveryId();
    if (recoveryId != null && recoveryId.isNotEmpty) {
      context['recovery_id'] = recoveryId;
    }
    return context;
  }
}
