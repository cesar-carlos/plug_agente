import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/errors.dart';

class PlaygroundProvider extends ChangeNotifier {
  PlaygroundProvider(
    this._executePlaygroundQuery,
    this._testDbConnection,
    this._executeStreamingQuery,
  );
  final ExecutePlaygroundQuery _executePlaygroundQuery;
  final TestDbConnection _testDbConnection;
  final ExecuteStreamingQuery _executeStreamingQuery;

  String _query = '';
  List<Map<String, dynamic>> _results = [];
  List<QueryResultSet> _resultSets = [];
  bool _isLoading = false;
  String? _error;
  String? _connectionStatus;
  bool? _isConnectionStatusSuccess;
  Duration? _executionDuration;
  int? _affectedRows;
  List<Map<String, dynamic>>? _columnMetadata;
  int _selectedResultSetIndex = 0;
  final CancellationToken _cancellationToken = CancellationToken();

  // Streaming support
  bool _isStreaming = false;
  int _rowsProcessed = 0;
  double _progress = 0;
  DateTime _lastStreamingNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _currentPage = 1;
  int _pageSize = 50;
  bool _hasNextPage = false;
  bool _hasExecutedQuery = false;
  bool _paginationAvailable = false;

  static const Duration _streamingUiUpdateInterval = Duration(
    milliseconds: 200,
  );
  static const int _progressEstimateOffset = 100;
  static const List<int> _pageSizeOptions = [25, 50, 100, 250];

  String get query => _query;
  List<Map<String, dynamic>> get results => selectedResultSet?.rows ?? _results;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get connectionStatus => _connectionStatus;
  bool? get isConnectionStatusSuccess => _isConnectionStatusSuccess;
  Duration? get executionDuration => _executionDuration;
  int? get affectedRows => _affectedRows;
  List<Map<String, dynamic>>? get columnMetadata =>
      selectedResultSet?.columnMetadata ?? _columnMetadata;
  CancellationToken get cancellationToken => _cancellationToken;
  List<QueryResultSet> get resultSets => _resultSets;
  QueryResultSet? get selectedResultSet {
    if (_resultSets.isEmpty) {
      return null;
    }
    if (_selectedResultSetIndex < 0 ||
        _selectedResultSetIndex >= _resultSets.length) {
      return _resultSets.first;
    }
    return _resultSets[_selectedResultSetIndex];
  }

  bool get hasMultipleResultSets => _resultSets.length > 1;
  int get selectedResultSetIndex => _selectedResultSetIndex;

  // Streaming getters
  bool get isStreaming => _isStreaming;
  int get rowsProcessed => _rowsProcessed;
  double get progress => _progress;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  bool get hasNextPage => _hasNextPage;
  bool get hasPreviousPage => _currentPage > 1;
  bool get hasPagination =>
      _paginationAvailable &&
      _hasExecutedQuery &&
      !_isStreaming &&
      _error == null;
  List<int> get pageSizeOptions => _pageSizeOptions;

  void setQuery(String value) {
    final shouldResetPagination = value != _query;
    _query = value;
    if (shouldResetPagination) {
      _currentPage = 1;
      _hasNextPage = false;
    }
    _clearError();
    notifyListeners();
  }

  Future<void> executeQuery({bool resetPagination = false}) async {
    if (resetPagination) {
      _currentPage = 1;
    }
    _clearError();
    _isLoading = true;
    _hasExecutedQuery = true;
    _paginationAvailable = true;
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
        pagination: QueryPaginationRequest(
          page: _currentPage,
          pageSize: _pageSize,
        ),
      );
      stopwatch.stop();
      _isLoading = false;

      result.fold(
        (response) {
          if (response.error != null) {
            _error = response.error;
            _results = [];
            _resultSets = [];
            _columnMetadata = null;
            _hasNextPage = false;
            _paginationAvailable = false;
          } else {
            _resultSets = response.resultSets;
            _selectedResultSetIndex = 0;
            _results = response.data;
            _affectedRows = response.affectedRows ?? 0;
            _columnMetadata =
                selectedResultSet?.columnMetadata ?? response.columnMetadata;
            _syncPaginationState(response.pagination);
          }
          _executionDuration = stopwatch.elapsed;
        },
        (failure) {
          _error = failure.toDisplayMessage();
          AppLogger.error(
            'Failed to execute query: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          _columnMetadata = null;
          _resultSets = [];
          _executionDuration = stopwatch.elapsed;
          _hasNextPage = false;
          _paginationAvailable = false;
        },
      );
    } on Exception catch (error, stackTrace) {
      stopwatch.stop();
      _isLoading = false;
      final failure = error.toFailure(
        message: 'Erro ao executar a consulta',
        context: {'operation': 'executeQuery'},
      );
      _error = failure.toDisplayMessage();
      _columnMetadata = null;
      _resultSets = [];
      _executionDuration = stopwatch.elapsed;
      _hasNextPage = false;
      _paginationAvailable = false;
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
    _connectionStatus = AppStrings.queryConnectionTesting;
    _isConnectionStatusSuccess = null;
    notifyListeners();

    final result = await _testDbConnection(config.connectionString);

    result.fold(
      (_) {
        _connectionStatus = AppStrings.queryConnectionSuccess;
        _isConnectionStatusSuccess = true;
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Failed to test connection: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        _connectionStatus = AppStrings.queryConnectionFailure;
        _isConnectionStatusSuccess = false;
      },
    );

    notifyListeners();
  }

  /// Executa query com streaming para grandes datasets.
  ///
  /// Processa os resultados em chunks, atualizando a UI progressivamente.
  /// Útil para queries que retornam milhares ou milhões de linhas.
  Future<void> executeQueryWithStreaming(
    String query,
    String connectionString,
  ) async {
    _clearError();
    _cancellationToken.reset();
    _isLoading = true;
    _isStreaming = true;
    _hasExecutedQuery = true;
    _paginationAvailable = false;
    _rowsProcessed = 0;
    _results = [];
    _resultSets = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _selectedResultSetIndex = 0;
    _progress = 0.0;
    _currentPage = 1;
    _hasNextPage = false;
    _lastStreamingNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // Executar streaming real com chunks incrementais
      final result = await _executeStreamingQuery(
        query,
        connectionString,
        (chunk) {
          // Callback chamado para cada chunk recebido
          _results.addAll(chunk);
          _rowsProcessed += chunk.length;
          _affectedRows = _rowsProcessed;

          // Atualizar progresso (estimativa simples)
          _progress =
              _rowsProcessed / (_rowsProcessed + _progressEstimateOffset);

          _notifyStreamingProgressIfNeeded();
        },
      );

      result.fold(
        (_) {
          _isStreaming = false;
          _progress = 1.0;
        },
        (failure) {
          _error = failure.toDisplayMessage();
          _isStreaming = false;
          AppLogger.error(
            'Streaming query failed: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
        },
      );

      notifyListeners();
    } on Exception catch (error, stackTrace) {
      _isLoading = false;
      _isStreaming = false;
      final failure = error.toFailure(
        message: AppStrings.queryStreamingErrorPrefix,
        context: {'operation': 'executeQueryWithStreaming'},
      );
      _error = failure.toDisplayMessage();
      AppLogger.error(
        'Streaming exception: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
      notifyListeners();
    } finally {
      stopwatch.stop();
      _executionDuration = stopwatch.elapsed;
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearResults() {
    _query = '';
    _results = [];
    _error = null;
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
    _currentPage = 1;
    _hasNextPage = false;
    _hasExecutedQuery = false;
    _paginationAvailable = false;
    _cancellationToken.reset();
    notifyListeners();
  }

  /// Cancela a query em execução.
  void cancelQuery() {
    if (_isLoading) {
      _cancellationToken.cancel();
      unawaited(
        (() async {
          try {
            await _executeStreamingQuery.cancelActiveStream();
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
      _error = AppStrings.queryCancelledByUser;
      notifyListeners();
    }
  }

  void _notifyStreamingProgressIfNeeded() {
    final now = DateTime.now();
    final shouldNotify =
        now.difference(_lastStreamingNotifyAt) >= _streamingUiUpdateInterval;
    if (!shouldNotify) {
      return;
    }

    _lastStreamingNotifyAt = now;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  Future<void> goToNextPage() async {
    if (_isLoading || !_hasNextPage) {
      return;
    }
    _currentPage++;
    await executeQuery();
  }

  Future<void> goToPreviousPage() async {
    if (_isLoading || _currentPage <= 1) {
      return;
    }
    _currentPage--;
    await executeQuery();
  }

  Future<void> setPageSize(int pageSize) async {
    if (_pageSize == pageSize) {
      return;
    }
    _pageSize = pageSize;
    _currentPage = 1;
    _hasNextPage = false;
    notifyListeners();

    if (_hasExecutedQuery && _query.trim().isNotEmpty && !_isStreaming) {
      await executeQuery();
    }
  }

  void setSelectedResultSetIndex(int index) {
    if (index < 0 || index >= _resultSets.length) {
      return;
    }
    _selectedResultSetIndex = index;
    _columnMetadata = _resultSets[index].columnMetadata;
    notifyListeners();
  }

  void _syncPaginationState(QueryPaginationInfo? pagination) {
    if (pagination == null) {
      _hasNextPage = false;
      _paginationAvailable = false;
      return;
    }

    _currentPage = pagination.page;
    _pageSize = pagination.pageSize;
    _hasNextPage = pagination.hasNextPage;
    _paginationAvailable = true;
  }
}
