import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/ports/i_playground_db_connection_gateway.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/presentation/mappers/playground_ui_strings.dart';
import 'package:plug_agente/presentation/providers/playground_query_controller.dart';
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
       ) {
    _queryController = _buildQueryController();
  }

  final ExecutePlaygroundQuery _executePlaygroundQuery;
  IPlaygroundDbConnectionGateway _dbConnectionGateway;
  final PlaygroundStreamingSession _streamingSession;
  PlaygroundUiStrings _ui;
  final PlaygroundQuerySession _querySession;
  late PlaygroundQueryController _queryController;

  PlaygroundQueryController _buildQueryController() {
    return PlaygroundQueryController(
      executePlaygroundQuery: _executePlaygroundQuery,
      streamingSession: _streamingSession,
      ui: _ui,
      dbConnectionGateway: _dbConnectionGateway,
    );
  }

  void bindDbConnectionGateway(IPlaygroundDbConnectionGateway gateway) {
    _dbConnectionGateway = gateway;
    _queryController = _buildQueryController();
  }

  void bindUiStrings(PlaygroundUiStrings strings) {
    _ui = strings;
    _querySession.bindUiStrings(strings);
    _queryController = _buildQueryController();
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

    final outcome = await _queryController.executeMaterializedQuery(
      query: _query,
      configId: effectiveConfigId,
      querySession: _querySession,
      sqlHandlingMode: _sqlHandlingMode,
    );
    _isLoading = false;
    _executionDuration = outcome.duration;

    if (outcome.response != null) {
      final response = outcome.response!;
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
      _queryController.syncDbConnectionIndicator(true);
    } else if (outcome.failure != null) {
      _error = outcome.errorMessage;
      _canRetry = outcome.canRetry;
      _columnMetadata = null;
      _resultSets = [];
      _querySession.disablePagination();
      _lastExecutionHint = null;
      _queryController.logExecuteQueryFailure(outcome.failure!);
      if (outcome.dbConnected == false) {
        _queryController.syncDbConnectionIndicator(false);
      }
    }

    notifyListeners();
  }

  Future<void> testConnection(Config config) async {
    _clearError();
    _connectionStatus = _ui.queryConnectionTesting;
    _isConnectionStatusSuccess = null;
    notifyListeners();

    final result = await _queryController.testConnection(config.connectionString);

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

    final outcome = await _queryController.executeStreamingQuery(
      query: query,
      connectionString: connectionString,
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
    );

    _executionDuration = outcome.duration;
    _isLoading = false;
    _isStreaming = false;

    if (outcome.completed) {
      _progress = 1.0;
      _canRetry = false;
      if (!_streamingSession.streamingStoppedByCap) {
        _lastExecutionHint = _querySession.buildStreamingExecutionHint(
          sqlHandlingMode: _sqlHandlingMode,
        );
      }
      _queryController.syncDbConnectionIndicator(true);
    } else if (outcome.failure != null) {
      _error = outcome.errorMessage;
      _canRetry = outcome.canRetry;
      if (!_streamingSession.streamingStoppedByCap) {
        _lastExecutionHint = null;
      }
      _queryController.logStreamingQueryFailure(outcome.failure!);
      if (outcome.dbConnected == false) {
        _queryController.syncDbConnectionIndicator(false);
      }
    }

    notifyListeners();
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
            await _queryController.cancelActiveStream();
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
    _queryController.logValidationExpected(QueryValidationMessages.queryCannotBeEmpty);
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
    _lastExecutionHint = null;
    _queryController.logValidationExpected(message);
    notifyListeners();
  }
}
