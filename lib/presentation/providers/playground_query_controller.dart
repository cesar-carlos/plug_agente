import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/ports/i_playground_db_connection_gateway.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/presentation/mappers/playground_ui_strings.dart';
import 'package:plug_agente/presentation/providers/playground_query_session.dart';
import 'package:plug_agente/presentation/providers/playground_streaming_session.dart';
import 'package:result_dart/result_dart.dart' as rd;

final class PlaygroundMaterializedExecuteOutcome {
  const PlaygroundMaterializedExecuteOutcome({
    required this.duration,
    this.response,
    this.failure,
    this.errorMessage,
    this.canRetry = false,
    this.dbConnected,
  });

  final Duration duration;
  final QueryResponse? response;
  final Object? failure;
  final String? errorMessage;
  final bool canRetry;
  final bool? dbConnected;
}

final class PlaygroundStreamingExecuteOutcome {
  const PlaygroundStreamingExecuteOutcome({
    required this.duration,
    this.failure,
    this.errorMessage,
    this.canRetry = false,
    this.dbConnected,
    this.completed = false,
  });

  final Duration duration;
  final Object? failure;
  final String? errorMessage;
  final bool canRetry;
  final bool? dbConnected;
  final bool completed;
}

class PlaygroundQueryController {
  PlaygroundQueryController({
    required ExecutePlaygroundQuery executePlaygroundQuery,
    required PlaygroundStreamingSession streamingSession,
    required PlaygroundUiStrings ui,
    required IPlaygroundDbConnectionGateway dbConnectionGateway,
  }) : _executePlaygroundQuery = executePlaygroundQuery,
       _streamingSession = streamingSession,
       _ui = ui,
       _dbConnectionGateway = dbConnectionGateway;

  final ExecutePlaygroundQuery _executePlaygroundQuery;
  final PlaygroundStreamingSession _streamingSession;
  final PlaygroundUiStrings _ui;
  final IPlaygroundDbConnectionGateway _dbConnectionGateway;

  String displayExecuteFailure(Object failure) {
    if (failure is ValidationFailure) {
      final m = failure.message;
      if (m == QueryValidationMessages.queryCannotBeEmpty) {
        return _ui.queryValidationEmpty;
      }
      if (m == QueryValidationMessages.connectionStringCannotBeEmpty) {
        return _ui.queryValidationConnectionStringEmpty;
      }
    }
    return failure.toDisplayMessage();
  }

  static bool failureIndicatesDbUnreachable(Object failure) {
    if (failure is ConnectionFailure || failure is DatabaseFailure) {
      return true;
    }
    if (failure is QueryExecutionFailure && failure.context['connectionFailed'] == true) {
      return true;
    }
    return false;
  }

  Failure failureFromQueryResponseError(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    if (normalized.contains('connection') ||
        normalized.contains('timeout') ||
        normalized.contains('network') ||
        normalized.contains('communication link')) {
      return ConnectionFailure.withContext(
        message: errorMessage,
        context: const {'connectionFailed': true},
      );
    }
    return QueryExecutionFailure.withContext(
      message: errorMessage,
      context: const {'operation': 'executeQuery'},
    );
  }

  Future<PlaygroundMaterializedExecuteOutcome> executeMaterializedQuery({
    required String query,
    required String? configId,
    required PlaygroundQuerySession querySession,
    required SqlHandlingMode sqlHandlingMode,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _executePlaygroundQuery(
        query,
        configId: configId,
        pagination: QueryPaginationRequest(
          page: querySession.currentPage,
          pageSize: querySession.pageSize,
        ),
        sqlHandlingMode: sqlHandlingMode,
      );
      stopwatch.stop();

      return result.fold(
        (response) {
          if (response.error != null) {
            final failure = failureFromQueryResponseError(response.error!);
            return PlaygroundMaterializedExecuteOutcome(
              duration: stopwatch.elapsed,
              failure: failure,
              errorMessage: displayExecuteFailure(failure),
              canRetry: failure.isTransient,
              dbConnected: false,
            );
          }
          return PlaygroundMaterializedExecuteOutcome(
            duration: stopwatch.elapsed,
            response: response,
            dbConnected: true,
          );
        },
        (failure) => PlaygroundMaterializedExecuteOutcome(
          duration: stopwatch.elapsed,
          failure: failure,
          errorMessage: displayExecuteFailure(failure),
          canRetry: failure is Failure && failure.isTransient,
          dbConnected: failureIndicatesDbUnreachable(failure) ? false : null,
        ),
      );
    } on Exception catch (error, stackTrace) {
      stopwatch.stop();
      final failure = ExceptionToFailureExtension(error).toFailure(
        message: _ui.queryExecuteUnexpectedError,
        context: const {'operation': 'executeQuery'},
      );
      AppLogger.error(
        'Query execution threw: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
      return PlaygroundMaterializedExecuteOutcome(
        duration: stopwatch.elapsed,
        failure: failure,
        errorMessage: failure.toDisplayMessage(),
        canRetry: failure.isTransient,
      );
    }
  }

  Future<PlaygroundStreamingExecuteOutcome> executeStreamingQuery({
    required String query,
    required String connectionString,
    required List<Map<String, dynamic>> results,
    required void Function(int rowsProcessed, double progress) onProgress,
    required void Function() notifyProgress,
    required void Function(int cap) onRowCapReached,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _streamingSession.executeStreamingQuery(
        query: query,
        connectionString: connectionString,
        onChunk: (chunk) => _streamingSession.processChunk(
          chunk: chunk,
          results: results,
          onProgress: onProgress,
          notifyProgress: notifyProgress,
          onRowCapReached: onRowCapReached,
        ),
      );

      stopwatch.stop();
      return result.fold(
        (_) => PlaygroundStreamingExecuteOutcome(
          duration: stopwatch.elapsed,
          completed: true,
          dbConnected: true,
        ),
        (failure) => PlaygroundStreamingExecuteOutcome(
          duration: stopwatch.elapsed,
          failure: failure,
          errorMessage: displayExecuteFailure(failure),
          canRetry: failure is Failure && failure.isTransient,
          dbConnected: failureIndicatesDbUnreachable(failure) ? false : null,
        ),
      );
    } on Exception catch (error, stackTrace) {
      stopwatch.stop();
      final failure = ExceptionToFailureExtension(error).toFailure(
        message: _ui.queryStreamingErrorPrefix,
        context: const {'operation': 'executeQueryWithStreaming'},
      );
      AppLogger.error(
        'Streaming exception: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
      return PlaygroundStreamingExecuteOutcome(
        duration: stopwatch.elapsed,
        failure: failure,
        errorMessage: failure.toDisplayMessage(),
        canRetry: failure.isTransient,
      );
    }
  }

  Future<rd.Result<bool>> testConnection(String connectionString) {
    return _dbConnectionGateway.testConnection(connectionString);
  }

  void syncDbConnectionIndicator(bool connected) {
    _dbConnectionGateway.syncConnectionIndicator(connected);
  }

  void logValidationExpected(String message) {
    if (kDebugMode) {
      AppLogger.info('Playground query validation: $message');
    } else {
      AppLogger.debug('Playground query validation: $message');
    }
  }

  void logExecuteQueryFailure(Object failure) {
    if (failure is ValidationFailure) {
      logValidationExpected(failure.toDisplayMessage());
      return;
    }
    AppLogger.error(
      'Failed to execute query: ${failure.toDisplayMessage()}',
      failure.toTechnicalMessage(),
    );
  }

  void logStreamingQueryFailure(Object failure) {
    if (failure is ValidationFailure) {
      logValidationExpected(failure.toDisplayMessage());
      return;
    }
    AppLogger.error(
      'Streaming query failed: ${failure.toDisplayMessage()}',
      failure.toTechnicalMessage(),
    );
  }

  Future<void> cancelActiveStream() => _streamingSession.cancelActiveStream();

  PlaygroundStreamingSession get streamingSession => _streamingSession;
}
