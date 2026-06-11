import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/ports/i_playground_db_connection_gateway.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/presentation/mappers/playground_ui_strings.dart';
import 'package:plug_agente/presentation/providers/playground_query_session.dart';
import 'package:plug_agente/presentation/providers/playground_streaming_session.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _NoOpPlaygroundDbConnectionGateway implements IPlaygroundDbConnectionGateway {
  @override
  Future<rd.Result<bool>> testConnection(String connectionString) {
    return Future<rd.Result<bool>>.value(
      rd.Failure(
        ConnectionFailure.withContext(
          message: 'Database connection gateway is not bound yet',
          context: const {'operation': 'playground_test_connection'},
        ),
      ),
    );
  }

  @override
  void syncConnectionIndicator(bool connected) {}
}

class PlaygroundProvider extends ChangeNotifier {
  PlaygroundProvider(
    this._executePlaygroundQuery,
    ExecuteStreamingQuery executeStreamingQuery, {
    IPlaygroundDbConnectionGateway? dbConnectionGateway,
    PlaygroundUiStrings? uiStrings,
  }) : _dbConnectionGateway = dbConnectionGateway ?? _NoOpPlaygroundDbConnectionGateway(),
       _ui = uiStrings ?? PlaygroundUiStrings.english,
       _querySession = PlaygroundQuerySession(uiStrings: uiStrings),
       _streamingSession = PlaygroundStreamingSession(
         executeStreamingQuery: executeStreamingQuery,
       );

  final ExecutePlaygroundQuery _executePlaygroundQuery;
  final PlaygroundStreamingSession _streamingSession;
  IPlaygroundDbConnectionGateway _dbConnectionGateway;
  PlaygroundUiStrings _ui;
  final PlaygroundQuerySession _querySession;

  void bindDbConnectionGateway(IPlaygroundDbConnectionGateway gateway) {
    _dbConnectionGateway = gateway;
  }

  void bindUiStrings(PlaygroundUiStrings strings) {
    _ui = strings;
    _querySession.bindUiStrings(strings);
  }

  String _displayExecuteFailure(Object failure) {
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

  void _notifyDbConnectionIndicator(bool connected) {
    _dbConnectionGateway.syncConnectionIndicator(connected);
  }

  static bool _failureIndicatesDbUnreachable(Object failure) {
    if (failure is ConnectionFailure || failure is DatabaseFailure) {
      return true;
    }
    if (failure is QueryExecutionFailure && failure.context['connectionFailed'] == true) {
      return true;
    }
    return false;
  }

  void _logValidationExpected(String message) {
    if (kDebugMode) {
      AppLogger.info('Playground query validation: $message');
    } else {
      AppLogger.debug('Playground query validation: $message');
    }
  }

  void _logExecuteQueryFailure(Object failure) {
    if (failure is ValidationFailure) {
      _logValidationExpected(failure.toDisplayMessage());
      return;
    }
    AppLogger.error(
      'Failed to execute query: ${failure.toDisplayMessage()}',
      failure.toTechnicalMessage(),
    );
  }

  void _logStreamingQueryFailure(Object failure) {
    if (failure is ValidationFailure) {
      _logValidationExpected(failure.toDisplayMessage());
      return;
    }
    AppLogger.error(
      'Streaming query failed: ${failure.toDisplayMessage()}',
      failure.toTechnicalMessage(),
    );
  }

  Failure _failureFromQueryResponseError(String errorMessage) {
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

  void _setExecuteFailure(Object failure) {
    _error = _displayExecuteFailure(failure);
    _canRetry = failure is Failure && failure.isTransient;
    _logExecuteQueryFailure(failure);
    if (_failureIndicatesDbUnreachable(failure)) {
      _notifyDbConnectionIndicator(false);
    }
  }

  void _rejectEmptyQuery() {
    _error = _ui.queryValidationEmpty;
    _canRetry = false;
    _isLoading = false;
    _querySession.markExecuted();
    _querySession.disablePagination();
    _results = [];
    _resultSets = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _selectedResultSetIndex = 0;
    _lastExecutionHint = null;
    _logValidationExpected(QueryValidationMessages.queryCannotBeEmpty);
    notifyListeners();
  }

  void _rejectStreamingValidation(String message) {
    _error = message;
    _canRetry = false;
    _isLoading = false;
    _isStreaming = false;
    _streamingSession.resetCapState();
    _querySession.markExecuted();
    _querySession.disablePagination();
    _rowsProcessed = 0;
    _progress = 0;
    _results = [];
    _resultSets = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _selectedResultSetIndex = 0;
    _querySession.resetPageForStreaming();
    _lastExecutionHint = null;
    _logValidationExpected(message);
    notifyListeners();
  }

  String _query = '';
  String? _currentConfigId;
  List<Map<String, dynamic>> _results = [];
  List<QueryResultSet> _resultSets = [];
  bool _isLoading = false;
  String? _error;
  bool _canRetry = false;
  String? _connectionStatus;
  bool? _isConnectionStatusSuccess;
  Duration? _executionDuration;
  int? _affectedRows;
  List<Map<String, dynamic>>? _columnMetadata;
  int _selectedResultSetIndex = 0;
  final CancellationToken _cancellationToken = CancellationToken();

  bool _isStreaming = false;
  int _rowsProcessed = 0;
  double _progress = 0;
  SqlHandlingMode _sqlHandlingMode = SqlHandlingMode.managed;
  String? _lastExecutionHint;

  String get query => _query;
  List<Map<String, dynamic>> get results => selectedResultSet?.rows ?? _results;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get canRetry => _canRetry;
  String? get connectionStatus => _connectionStatus;
  bool? get isConnectionStatusSuccess => _isConnectionStatusSuccess;
  Duration? get executionDuration => _executionDuration;
  int? get affectedRows => _affectedRows;
  List<Map<String, dynamic>>? get columnMetadata => selectedResultSet?.columnMetadata ?? _columnMetadata;
  CancellationToken get cancellationToken => _cancellationToken;
  List<QueryResultSet> get resultSets => _resultSets;
  QueryResultSet? get selectedResultSet {
    if (_resultSets.isEmpty) {
      return null;
    }
    if (_selectedResultSetIndex < 0 || _selectedResultSetIndex >= _resultSets.length) {
      return _resultSets.first;
    }
    return _resultSets[_selectedResultSetIndex];
  }

  bool get hasMultipleResultSets => _resultSets.length > 1;
  int get selectedResultSetIndex => _selectedResultSetIndex;

  bool get isStreaming => _isStreaming;
  int get rowsProcessed => _rowsProcessed;
  double get progress => _progress;
  int get currentPage => _querySession.currentPage;
  int get pageSize => _querySession.pageSize;
  bool get hasNextPage => _querySession.hasNextPage;
  bool get hasPreviousPage => _querySession.hasPreviousPage;
  bool get hasPagination => _querySession.hasPagination(isStreaming: _isStreaming, error: _error);
  List<int> get pageSizeOptions => PlaygroundQuerySession.pageSizeOptions;
  SqlHandlingMode get sqlHandlingMode => _sqlHandlingMode;
  String? get lastExecutionHint => _lastExecutionHint;

  bool get streamingStoppedByRowCap => _streamingSession.streamingStoppedByCap;

  void setSqlHandlingMode(SqlHandlingMode mode) {
    if (_sqlHandlingMode == mode) return;
    _sqlHandlingMode = mode;
    notifyListeners();
  }

  void setQuery(String value) {
    final shouldResetPagination = value != _query;
    _query = value;
    if (shouldResetPagination) {
      _querySession.resetPaginationForQueryChange();
    }
    _clearError();
    notifyListeners();
  }

  Future<void> executeQuery({
    bool resetPagination = false,
    String? configId,
  }) async {
    if (_isLoading) return;

    final effectiveConfigId = configId ?? _currentConfigId;
    _currentConfigId = effectiveConfigId;
    if (resetPagination) {
      _querySession.resetPaginationForQueryChange();
    }
    _clearError();
    _lastExecutionHint = null;

    if (_query.trim().isEmpty) {
      _rejectEmptyQuery();
      return;
    }

    _isLoading = true;
    _querySession.markExecuted();
    _results = [];
    _resultSets = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _selectedResultSetIndex = 0;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      final result = await _executePlaygroundQuery(
        _query,
        configId: effectiveConfigId,
        pagination: QueryPaginationRequest(
          page: _querySession.currentPage,
          pageSize: _querySession.pageSize,
        ),
        sqlHandlingMode: _sqlHandlingMode,
      );
      stopwatch.stop();
      _isLoading = false;

      result.fold(
        (response) {
          if (response.error != null) {
            final failure = _failureFromQueryResponseError(response.error!);
            _setExecuteFailure(failure);
            _results = [];
            _resultSets = [];
            _columnMetadata = null;
            _querySession.disablePagination();
            _lastExecutionHint = null;
          } else {
            _canRetry = false;
            _resultSets = response.resultSets;
            _selectedResultSetIndex = 0;
            _results = response.data;
            _affectedRows = response.affectedRows ?? 0;
            _columnMetadata = selectedResultSet?.columnMetadata ?? response.columnMetadata;
            _querySession.syncFromResponse(response.pagination);
            _lastExecutionHint = _querySession.buildLastExecutionHint(
              sqlHandlingMode: _sqlHandlingMode,
              pagination: response.pagination,
            );
            _notifyDbConnectionIndicator(true);
          }
          _executionDuration = stopwatch.elapsed;
        },
        (failure) {
          _setExecuteFailure(failure);
          _columnMetadata = null;
          _resultSets = [];
          _executionDuration = stopwatch.elapsed;
          _querySession.disablePagination();
          _lastExecutionHint = null;
        },
      );
    } on Exception catch (error, stackTrace) {
      stopwatch.stop();
      _isLoading = false;
      final failure = ExceptionToFailureExtension(error).toFailure(
        message: _ui.queryExecuteUnexpectedError,
        context: {'operation': 'executeQuery'},
      );
      _error = failure.toDisplayMessage();
      _canRetry = failure.isTransient;
      _columnMetadata = null;
      _resultSets = [];
      _executionDuration = stopwatch.elapsed;
      _querySession.disablePagination();
      _lastExecutionHint = null;
      AppLogger.error(
        'Query execution threw: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    }

    notifyListeners();
  }

  Future<void> testConnection(Config config) async {
    _clearError();
    _connectionStatus = _ui.queryConnectionTesting;
    _isConnectionStatusSuccess = null;
    notifyListeners();

    final result = await _dbConnectionGateway.testConnection(config.connectionString);

    result.fold(
      (_) {
        _connectionStatus = _ui.queryConnectionSuccess;
        _isConnectionStatusSuccess = true;
      },
      (failure) {
        _error = failure.toDisplayMessageWithOdbcDetail();
        AppLogger.error(
          'Failed to test connection: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        _connectionStatus = _ui.queryConnectionFailure;
        _isConnectionStatusSuccess = false;
      },
    );

    notifyListeners();
  }

  Future<void> executeQueryWithStreaming(
    String query,
    String connectionString,
  ) async {
    _clearError();
    _lastExecutionHint = null;
    _streamingSession.resetCapState();
    _cancellationToken.reset();

    if (query.trim().isEmpty) {
      _rejectStreamingValidation(_ui.queryValidationEmpty);
      return;
    }
    if (connectionString.trim().isEmpty) {
      _rejectStreamingValidation(
        _ui.queryValidationConnectionStringEmpty,
      );
      return;
    }

    _isLoading = true;
    _isStreaming = true;
    _querySession.markExecuted();
    _querySession.resetPageForStreaming();
    _rowsProcessed = 0;
    _results = [];
    _resultSets = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _selectedResultSetIndex = 0;
    _progress = 0.0;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      final result = await _executeStreamingQueryFromSession(
        query,
        connectionString,
      );

      result.fold(
        (_) {
          _isStreaming = false;
          _progress = 1.0;
          _canRetry = false;
          if (!_streamingSession.streamingStoppedByCap) {
            _lastExecutionHint = _querySession.buildStreamingExecutionHint(
              sqlHandlingMode: _sqlHandlingMode,
            );
          }
          _notifyDbConnectionIndicator(true);
        },
        (failure) {
          _error = _displayExecuteFailure(failure);
          _canRetry = failure is Failure && failure.isTransient;
          _isStreaming = false;
          if (!_streamingSession.streamingStoppedByCap) {
            _lastExecutionHint = null;
          }
          _logStreamingQueryFailure(failure);
          if (_failureIndicatesDbUnreachable(failure)) {
            _notifyDbConnectionIndicator(false);
          }
        },
      );
    } on Exception catch (error, stackTrace) {
      _isLoading = false;
      _isStreaming = false;
      final failure = ExceptionToFailureExtension(error).toFailure(
        message: _ui.queryStreamingErrorPrefix,
        context: {'operation': 'executeQueryWithStreaming'},
      );
      _error = failure.toDisplayMessage();
      _canRetry = failure.isTransient;
      AppLogger.error(
        'Streaming exception: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    } finally {
      stopwatch.stop();
      _executionDuration = stopwatch.elapsed;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<rd.Result<void>> _executeStreamingQueryFromSession(
    String query,
    String connectionString,
  ) {
    return _streamingSession.executeStreamingQuery(
      query: query,
      connectionString: connectionString,
      onChunk: (chunk) => _streamingSession.processChunk(
        chunk: chunk,
        results: _results,
        onProgress: (rowsProcessed, progress) {
          _rowsProcessed = rowsProcessed;
          _affectedRows = rowsProcessed;
          _progress = progress;
        },
        notifyProgress: notifyListeners,
        onRowCapReached: (cap) {
          _lastExecutionHint = _ui.streamingRowCapHint(cap);
        },
      ),
    );
  }

  void clearResults() {
    _query = '';
    _results = [];
    _error = null;
    _canRetry = false;
    _executionDuration = null;
    _affectedRows = null;
    _connectionStatus = null;
    _isConnectionStatusSuccess = null;
    _columnMetadata = null;
    _resultSets = [];
    _isStreaming = false;
    _rowsProcessed = 0;
    _progress = 0.0;
    _selectedResultSetIndex = 0;
    _querySession.resetForClear();
    _lastExecutionHint = null;
    _streamingSession.resetCapState();
    _cancellationToken.reset();
    notifyListeners();
  }

  void cancelQuery() {
    if (_isLoading) {
      _cancellationToken.cancel();
      unawaited(
        (() async {
          try {
            await _streamingSession.cancelActiveStream();
          } on Exception catch (e, s) {
            AppLogger.warning(
              'Failed to cancel active stream',
              e,
              s,
            );
          }
        })(),
      );
      _isLoading = false;
      _isStreaming = false;
      _error = _ui.queryCancelledByUser;
      _canRetry = false;
      notifyListeners();
    }
  }

  void _clearError() {
    _error = null;
    _canRetry = false;
  }

  Future<void> goToNextPage() async {
    if (_isLoading || _querySession.advancePage() == null) {
      return;
    }
    await executeQuery();
  }

  Future<void> goToPreviousPage() async {
    if (_isLoading || _querySession.retreatPage() == null) {
      return;
    }
    await executeQuery();
  }

  Future<void> setPageSize(int pageSize) async {
    if (_querySession.pageSize == pageSize) {
      return;
    }
    _querySession.setPageSize(pageSize);
    notifyListeners();

    if (_querySession.hasExecutedQuery && _query.trim().isNotEmpty && !_isStreaming) {
      await executeQuery();
    }
  }

  void setSelectedResultSetIndex(int index) {
    if (!_querySession.setSelectedResultSetIndex(index, _resultSets.length)) {
      return;
    }
    _selectedResultSetIndex = index;
    _columnMetadata = _resultSets[index].columnMetadata;
    notifyListeners();
  }
}
