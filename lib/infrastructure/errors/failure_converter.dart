import 'dart:io';

import 'package:dio/dio.dart';
import 'package:plug_agente/domain/errors/errors.dart';

/// Helper utilities for converting exceptions to failures
/// at infrastructure boundaries.
///
/// Usage:
/// ```dart
/// try {
///   await someOperation();
/// } catch (e, st) {
///   return FailureConverter.convert(e, st, operation: 'connect');
/// }
/// ```
class FailureConverter {
  FailureConverter._();

  /// Converts an exception to an appropriate [Failure] type.
  ///
  /// Uses exception type and message content to determine the most
  /// appropriate failure type. The [stackTrace] is intentionally NOT stored
  /// in [Failure.context] to prevent traces from leaking to RPC payloads;
  /// callers should log it separately via developer.log before calling this.
  static Failure convert(
    Object exception,
    StackTrace stackTrace, {
    String? operation,
    Map<String, dynamic> additionalContext = const {},
  }) {
    final context = <String, dynamic>{
      ...?(operation != null ? {'operation': operation} : null),
      ...additionalContext,
    };

    if (exception is DioException) {
      return _mapDioException(exception, context);
    }

    // Direct exception handling for known types
    if (exception is FormatException) {
      return ValidationFailure.withContext(
        message: _validationMessage,
        cause: exception,
        context: _withTechnicalDetail(exception, context),
      );
    }

    if (exception is ArgumentError) {
      return ValidationFailure.withContext(
        message: _validationMessage,
        cause: exception,
        context: _withTechnicalDetail(exception, context),
      );
    }

    if (exception is StateError) {
      return ValidationFailure.withContext(
        message: _stateErrorMessage,
        cause: exception,
        context: _withTechnicalDetail(exception, context),
      );
    }

    // For SocketException - capture address info
    if (exception is SocketException) {
      return NetworkFailure.withContext(
        message: _networkMessage,
        cause: exception,
        context: _withTechnicalDetail(
          exception,
          {
            ...context,
            'address': exception.address?.host,
          },
        ),
      );
    }

    // For ODBC/Database-related errors
    final errorString = exception.toString().toLowerCase();
    if (errorString.contains('odbc') || errorString.contains('sql') || errorString.contains('database')) {
      if (errorString.contains('connection') || errorString.contains('connect')) {
        return ConnectionFailure.withContext(
          message: _connectionMessage,
          cause: exception,
          context: _withTechnicalDetail(exception, context),
        );
      }
      if (errorString.contains('query') || errorString.contains('execute') || errorString.contains('syntax')) {
        final isTimeout = errorString.contains('timeout');
        return QueryExecutionFailure.withContext(
          message: _queryExecutionMessage,
          cause: exception,
          context: _withTechnicalDetail(
            exception,
            {
              ...context,
              if (isTimeout) 'timeout': true,
              if (isTimeout) 'timeout_stage': 'sql',
            },
          ),
        );
      }
      return DatabaseFailure.withContext(
        message: _databaseMessage,
        cause: exception,
        context: _withTechnicalDetail(exception, context),
      );
    }

    // For network-related errors (incl. transport timeout)
    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      final isTimeout = errorString.contains('timeout');
      return NetworkFailure.withContext(
        message: _networkMessage,
        cause: exception,
        context: _withTechnicalDetail(
          exception,
          {
            ...context,
            if (isTimeout) 'timeout': true,
            if (isTimeout) 'timeout_stage': 'transport',
          },
        ),
      );
    }

    // Default: server error
    return ServerFailure.withContext(
      message: _serverMessage(exception),
      cause: exception,
      context: _withTechnicalDetail(exception, context),
    );
  }

  static const String _validationMessage = 'The provided input is invalid.';
  static const String _stateErrorMessage = 'The operation is not allowed in the current state.';
  static const String _networkMessage = 'Unable to reach the remote endpoint.';
  static const String _connectionMessage = 'Unable to connect to the database.';
  static const String _queryExecutionMessage = 'The query could not be executed.';
  static const String _databaseMessage = 'A database error occurred.';

  static String _serverMessage(Object exception) {
    final detail = _technicalDetail(exception);
    if (detail.isEmpty || detail == 'Exception') {
      return 'An error occurred';
    }
    return 'An unexpected error occurred.';
  }

  static String _technicalDetail(Object exception) {
    if (exception is Failure) {
      return exception.message;
    }

    return exception.toString();
  }

  static Map<String, dynamic> _withTechnicalDetail(
    Object exception,
    Map<String, dynamic> context,
  ) {
    final detail = _technicalDetail(exception);
    if (detail.isEmpty || detail == 'Exception') {
      return context;
    }

    return {
      ...context,
      'technical_message': detail,
    };
  }

  static String _dioUserMessage(DioException exception) {
    return switch (exception.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'The request timed out.',
      DioExceptionType.connectionError => 'Unable to reach the remote endpoint.',
      DioExceptionType.badCertificate => 'The secure connection could not be established.',
      DioExceptionType.cancel => 'The request was cancelled.',
      DioExceptionType.badResponse => _dioBadResponseMessage(exception),
      DioExceptionType.unknown => _serverMessage(exception),
    };
  }

  static String _dioBadResponseMessage(DioException exception) {
    final statusCode = exception.response?.statusCode ?? 0;
    if (statusCode >= 500 && statusCode < 600) {
      return 'The remote service is temporarily unavailable.';
    }
    if (statusCode >= 400 && statusCode < 500) {
      return 'The request was rejected by the remote service.';
    }
    return 'The remote service returned an unexpected response.';
  }

  static Failure _mapDioException(DioException exception, Map<String, dynamic> context) {
    final dioContext = <String, dynamic>{
      ...context,
      'dio_type': exception.type.name,
      if (exception.response?.statusCode != null) 'http_status': exception.response!.statusCode,
    };

    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return NetworkFailure.withContext(
          message: _dioUserMessage(exception),
          cause: exception,
          context: _withTechnicalDetail(exception, dioContext),
        );
      case DioExceptionType.badResponse:
        final statusCode = exception.response?.statusCode ?? 0;
        if (statusCode >= 500 && statusCode < 600) {
          return NetworkFailure.withContext(
            message: _dioUserMessage(exception),
            cause: exception,
            context: _withTechnicalDetail(exception, dioContext),
          );
        }
        if (statusCode >= 400 && statusCode < 500) {
          return ValidationFailure.withContext(
            message: _dioUserMessage(exception),
            cause: exception,
            context: _withTechnicalDetail(exception, dioContext),
          );
        }
        return NetworkFailure.withContext(
          message: _dioUserMessage(exception),
          cause: exception,
          context: _withTechnicalDetail(exception, dioContext),
        );
      case DioExceptionType.cancel:
        return NetworkFailure.withContext(
          message: _dioUserMessage(exception),
          cause: exception,
          context: _withTechnicalDetail(
            exception,
            {
              ...dioContext,
              'cancelled': true,
            },
          ),
        );
      case DioExceptionType.unknown:
        break;
    }

    final lower = exception.toString().toLowerCase();
    if (lower.contains('socket') || lower.contains('connection') || lower.contains('timeout')) {
      return NetworkFailure.withContext(
        message: _networkMessage,
        cause: exception,
        context: _withTechnicalDetail(exception, dioContext),
      );
    }

    return ServerFailure.withContext(
      message: _serverMessage(exception),
      cause: exception,
      context: _withTechnicalDetail(exception, dioContext),
    );
  }

  /// Wraps an exception with additional context for debugging.
  ///
  /// Use this when you need to preserve stack trace information.
  /// If exception is already a Failure, enriches it directly.
  static Failure withContext(
    Object exception,
    StackTrace stackTrace, {
    required String message,
    Map<String, dynamic> context = const {},
    String? code,
  }) {
    // If already a Failure, enrich it directly to preserve type
    if (exception is Failure) {
      final failure = exception;

      // Enrich context with additional information
      final enrichedContext = {
        ...failure.context,
        ...?(code != null ? {'originalCode': code} : null),
        ...context,
      };

      // Create new failure with same type but enriched context
      if (failure is ValidationFailure) {
        return ValidationFailure.withContext(
          message: message,
          context: enrichedContext,
          cause: failure.cause,
        );
      }
      if (failure is NetworkFailure) {
        return NetworkFailure.withContext(
          message: message,
          context: enrichedContext,
          cause: failure.cause,
        );
      }
      if (failure is DatabaseFailure) {
        return DatabaseFailure.withContext(
          message: message,
          context: enrichedContext,
          cause: failure.cause,
        );
      }
      if (failure is ConnectionFailure) {
        return ConnectionFailure.withContext(
          message: message,
          context: enrichedContext,
          cause: failure.cause,
        );
      }
      if (failure is QueryExecutionFailure) {
        return QueryExecutionFailure.withContext(
          message: message,
          context: enrichedContext,
          cause: failure.cause,
        );
      }
      // Fallback for other failure types
      return ServerFailure.withContext(
        message: message,
        context: enrichedContext,
        cause: failure.cause,
      );
    }

    // For regular exceptions, convert first then enrich
    final baseFailure = convert(exception, stackTrace);

    // Enrich context with additional information
    final enrichedContext = {
      ...baseFailure.context,
      ...?(code != null ? {'originalCode': code} : null),
      ...context,
    };

    // Create a new failure with enriched context
    // Note: Since Failure is abstract, we need to handle each type
    if (baseFailure is ValidationFailure) {
      return ValidationFailure.withContext(
        message: message,
        context: enrichedContext,
        cause: baseFailure.cause,
      );
    }
    if (baseFailure is NetworkFailure) {
      return NetworkFailure.withContext(
        message: message,
        context: enrichedContext,
        cause: baseFailure.cause,
      );
    }
    if (baseFailure is DatabaseFailure) {
      return DatabaseFailure.withContext(
        message: message,
        context: enrichedContext,
        cause: baseFailure.cause,
      );
    }
    if (baseFailure is ConnectionFailure) {
      return ConnectionFailure.withContext(
        message: message,
        context: enrichedContext,
        cause: baseFailure.cause,
      );
    }
    if (baseFailure is QueryExecutionFailure) {
      return QueryExecutionFailure.withContext(
        message: message,
        context: enrichedContext,
        cause: baseFailure.cause,
      );
    }
    // Fallback for other types
    return ServerFailure.withContext(
      message: message,
      context: enrichedContext,
      cause: baseFailure.cause,
    );
  }
}
