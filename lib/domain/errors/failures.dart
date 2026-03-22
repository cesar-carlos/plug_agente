import 'dart:developer' as developer;

abstract class Failure implements Exception {
  Failure(this.message, String defaultCode)
    : _code = defaultCode,
      cause = null,
      timestamp = DateTime.now(),
      context = const {};

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

  String get code => _code;

  bool get isRecoverable => false;

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
  bool get isTransient => true;
}

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
  bool get isTransient => true;
}

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
  bool get isRecoverable => true;
}

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
  bool get isRecoverable => true;
}

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
  bool get isRecoverable => true;
}

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
  bool get isRecoverable => true;
}

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
  bool get isTransient => true;
}

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
  bool get isRecoverable => true;
}

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
  bool get isTransient => true;
}

/// JSON (or other payload) encode/decode failed — distinct from wire compression.
class PayloadEncodingFailure extends Failure {
  PayloadEncodingFailure(String message) : super(message, 'PAYLOAD_ENCODING_ERROR');

  PayloadEncodingFailure.withContext({
    required super.message,
    super.code,
    super.cause,
    super.timestamp,
    super.context,
  }) : super.withContext(
         defaultCode: 'PAYLOAD_ENCODING_ERROR',
       );

  @override
  bool get isRecoverable => true;
}

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
  bool get isTransient => true;
}
