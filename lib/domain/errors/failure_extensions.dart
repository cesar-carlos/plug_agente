import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart';

extension ObjectFailureExtension on Object {
  String toUserMessage() {
    if (this is Failure) {
      final failure = this as Failure;
      final userMessage = failure.context['user_message'] as String?;
      if (userMessage != null && userMessage.trim().isNotEmpty) {
        return userMessage;
      }
      return failure.message;
    }
    return toString();
  }

  String toDisplayMessage() {
    final message = toUserMessage();
    if (_isBufferTooSmallMessage(message)) {
      return 'Resultado muito grande para o buffer atual. '
          'Ative o modo streaming ou aumente "Buffer de resultados (MB)" '
          'nas configurações avançadas.';
    }
    if (_isCancelledMessage(message)) {
      return 'A consulta foi cancelada.';
    }
    return message;
  }

  /// Returns display message with ODBC/technical details when available.
  /// Use for connection test errors to help diagnose driver/network issues.
  String toDisplayMessageWithOdbcDetail() {
    final base = toDisplayMessage();
    if (this is! Failure) return base;

    final failure = this as Failure;
    final odbcMessage = failure.context['odbc_message'] as String?;
    if (odbcMessage == null || odbcMessage.trim().isEmpty) return base;

    return '$base\n\nDetalhe ODBC: $odbcMessage';
  }

  String toTechnicalMessage() {
    if (this is Failure) {
      return (this as Failure).toString();
    }
    return toString();
  }

  bool get isFailure => this is Failure;

  Failure? get asFailure => this is Failure ? this as Failure : null;

  bool _isBufferTooSmallMessage(String message) {
    return message.toLowerCase().contains('buffer too small');
  }

  bool _isCancelledMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('cancelado pelo usuário') ||
        normalized.contains('consulta foi cancelada') ||
        normalized.contains('streaming cancelado');
  }
}

extension ExceptionToFailureExtension on Object {
  Failure toFailure({
    String? message,
    Map<String, dynamic> context = const {},
  }) {
    final errorMessage = message ?? toString();

    if (this is FormatException ||
        this is ArgumentError ||
        this is StateError ||
        this is NoSuchMethodError) {
      return ValidationFailure.withContext(
        message: errorMessage,
        context: context,
        cause: this,
      );
    }

    final errorString = toString().toLowerCase();
    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return NetworkFailure.withContext(
        message: errorMessage,
        context: context,
        cause: this,
      );
    }

    if (errorString.contains('database') ||
        errorString.contains('odbc') ||
        errorString.contains('sql') ||
        errorString.contains('query')) {
      return DatabaseFailure.withContext(
        message: errorMessage,
        context: context,
        cause: this,
      );
    }

    return ServerFailure.withContext(
      message: errorMessage,
      context: context,
      cause: this,
    );
  }
}

extension ResultLoggingExtension on Object {
  String logError(
    String operation, {
    Map<String, dynamic> context = const {},
  }) {
    final failure = asFailure;
    final contextSuffix = context.isEmpty ? '' : ' | context: $context';
    if (failure != null) {
      AppLogger.error(
        '$operation: ${failure.message}$contextSuffix',
        failure.toString(),
      );
      return failure.message;
    }

    AppLogger.error('$operation: ${toUserMessage()}$contextSuffix', this);
    return toUserMessage();
  }

  bool get requiresModalDialog {
    if (!isFailure) {
      return false;
    }

    final failure = this as Failure;
    return failure is ConfigurationFailure ||
        failure is ConnectionFailure ||
        failure is ServerFailure;
  }

  bool get isUserRecoverable {
    if (!isFailure) {
      return false;
    }

    final failure = this as Failure;
    return failure.isRecoverable;
  }
}
