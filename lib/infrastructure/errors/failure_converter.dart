import 'dart:io';
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
  /// appropriate failure type. Captures stack trace and enriches context.
  static Failure convert(
    Object exception,
    StackTrace stackTrace, {
    String? operation,
    Map<String, dynamic> additionalContext = const {},
  }) {
    final context = {
      'operation': ?operation,
      ...additionalContext,
    };

    // Direct exception handling for known types
    if (exception is FormatException) {
      return ValidationFailure.withContext(
        message: exception.toString(),
        cause: exception,
        context: context,
      );
    }

    if (exception is ArgumentError) {
      return ValidationFailure.withContext(
        message: exception.toString(),
        cause: exception,
        context: context,
      );
    }

    if (exception is StateError) {
      return ValidationFailure.withContext(
        message: exception.toString(),
        cause: exception,
        context: context,
      );
    }

    // For SocketException - capture address info
    if (exception is SocketException) {
      return NetworkFailure.withContext(
        message: _extractMessage(exception),
        cause: exception,
        context: {
          ...context,
          'address': exception.address?.host,
        },
      );
    }

    // For ODBC/Database-related errors
    final errorString = exception.toString().toLowerCase();
    if (errorString.contains('odbc') ||
        errorString.contains('sql') ||
        errorString.contains('database')) {
      if (errorString.contains('connection') ||
          errorString.contains('connect')) {
        return ConnectionFailure.withContext(
          message: _extractMessage(exception),
          cause: exception,
          context: context,
        );
      }
      if (errorString.contains('query') ||
          errorString.contains('execute') ||
          errorString.contains('syntax')) {
        return QueryExecutionFailure.withContext(
          message: _extractMessage(exception),
          cause: exception,
          context: context,
        );
      }
      return DatabaseFailure.withContext(
        message: _extractMessage(exception),
        cause: exception,
        context: context,
      );
    }

    // For network-related errors
    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return NetworkFailure.withContext(
        message: _extractMessage(exception),
        cause: exception,
        context: context,
      );
    }

    // Default: server error
    return ServerFailure.withContext(
      message: _extractMessage(exception),
      cause: exception,
      context: context,
    );
  }

  /// Extracts a meaningful error message from an exception.
  ///
  /// Returns the exception's message or a default message if unavailable.
  static String _extractMessage(Object exception) {
    if (exception is Failure) {
      return exception.message;
    }

    final string = exception.toString();
    if (string.isNotEmpty && string != 'Exception') {
      return string;
    }

    return 'An error occurred';
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
        'originalCode': ?code,
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
      'originalCode': ?code,
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
