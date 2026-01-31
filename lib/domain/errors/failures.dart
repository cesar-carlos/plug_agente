import 'dart:developer' as developer;

/// Base class for all domain failures.
///
/// Provides structured error information with:
/// - Message: Human-readable description
/// - Code: Machine-readable error identifier
/// - Cause: Original exception (if any)
/// - Timestamp: When the error occurred
/// - Context: Additional metadata
/// - Recoverability: Whether user can recover from this error
/// - Transience: Whether error is temporary/retryable
abstract class Failure implements Exception {
  /// Simple constructor with message only (backward compatible).
  Failure(this.message, String defaultCode)
    : _code = defaultCode,
      cause = null,
      timestamp = DateTime.now(),
      context = const {};

  /// Extended constructor with all fields.
  Failure.withContext({
    required this.message,
    required String defaultCode,
    String? code,
    this.cause,
    DateTime? timestamp,
    this.context = const {},
  }) : _code = code ?? defaultCode,
       timestamp = timestamp ?? DateTime.now();
  final String message;
  final String _code;
  final Object? cause;
  final DateTime timestamp;
  final Map<String, dynamic> context;

  /// Get the error code.
  String get code => _code;

  /// Whether this error can be recovered from by user action.
  ///
  /// Examples of recoverable errors:
  /// - ValidationFailure (user can fix input)
  /// - ConfigurationFailure (user can update config)
  /// - NotFoundFailure (user can create resource)
  ///
  /// Override in subclasses for specific behavior.
  bool get isRecoverable => false;

  /// Whether this error is temporary/transient.
  ///
  /// Transient errors may succeed on retry:
  /// - NetworkFailure (temporary network issues)
  /// - ConnectionFailure (server temporarily unavailable)
  ///
  /// Override in subclasses for specific behavior.
  bool get isTransient => false;

  @override
  String toString() {
    final buffer = StringBuffer('[$code] $message');

    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }

    if (context.isNotEmpty) {
      buffer.write('\nContext: $context');
    }

    return buffer.toString();
  }

  /// Log this failure with structured logging.
  void log() {
    developer.log(
      message,
      name: 'failure',
      level: 1000,
      error: cause,
      time: timestamp,
    );
  }
}

/// Server-side error (HTTP 5xx, API errors).
class ServerFailure extends Failure {
  ServerFailure(String message) : super(message, 'SERVER_ERROR');

  ServerFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'SERVER_ERROR',
       );

  @override
  bool get isTransient => true; // Server errors may be temporary
}

/// Network connectivity error.
class NetworkFailure extends Failure {
  NetworkFailure(String message) : super(message, 'NETWORK_ERROR');

  NetworkFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'NETWORK_ERROR',
       );

  @override
  bool get isTransient => true; // Network issues are often temporary
}

/// Database operation error.
class DatabaseFailure extends Failure {
  DatabaseFailure(String message) : super(message, 'DATABASE_ERROR');

  DatabaseFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'DATABASE_ERROR',
       );

  @override
  bool get isRecoverable => true; // User may fix query/data
}

/// Input validation error.
class ValidationFailure extends Failure {
  ValidationFailure(String message) : super(message, 'VALIDATION_ERROR');

  ValidationFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'VALIDATION_ERROR',
       );

  @override
  bool get isRecoverable => true; // User can fix invalid input
}

/// Resource not found error.
class NotFoundFailure extends Failure {
  NotFoundFailure(String message) : super(message, 'NOT_FOUND');

  NotFoundFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'NOT_FOUND',
       );

  @override
  bool get isRecoverable => true; // User can create the resource
}

/// Configuration error (missing/invalid config).
class ConfigurationFailure extends Failure {
  ConfigurationFailure(String message) : super(message, 'CONFIG_ERROR');

  ConfigurationFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'CONFIG_ERROR',
       );

  @override
  bool get isRecoverable => true; // User can fix configuration
}

/// Database connection error.
class ConnectionFailure extends Failure {
  ConnectionFailure(String message) : super(message, 'CONNECTION_ERROR');

  ConnectionFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'CONNECTION_ERROR',
       );

  @override
  bool get isTransient => true; // Connection issues may be temporary
}

/// SQL query execution error.
class QueryExecutionFailure extends Failure {
  QueryExecutionFailure(String message) : super(message, 'QUERY_ERROR');

  QueryExecutionFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'QUERY_ERROR',
       );

  @override
  bool get isRecoverable => true; // User can fix the query
}

/// Data compression/decompression error.
class CompressionFailure extends Failure {
  CompressionFailure(String message) : super(message, 'COMPRESSION_ERROR');

  CompressionFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'COMPRESSION_ERROR',
       );

  @override
  bool get isTransient => true; // May succeed on retry
}

/// Notification system error.
class NotificationFailure extends Failure {
  NotificationFailure(String message) : super(message, 'NOTIFICATION_ERROR');

  NotificationFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'NOTIFICATION_ERROR',
       );

  @override
  bool get isTransient => true; // Notification may work on retry
}
