import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
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
  bool _isLoading = false;
  String? _error;
  String? _connectionStatus;
  bool? _isConnectionStatusSuccess;
  Duration? _executionDuration;
  int? _affectedRows;
  List<Map<String, dynamic>>? _columnMetadata;
  final CancellationToken _cancellationToken = CancellationToken();

  // Streaming support
  bool _isStreaming = false;
  int _rowsProcessed = 0;
  double _progress = 0;
  DateTime _lastStreamingNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _streamingUiUpdateInterval = Duration(
    milliseconds: 200,
  );
  static const int _progressEstimateOffset = 100;

  String get query => _query;
  List<Map<String, dynamic>> get results => _results;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get connectionStatus => _connectionStatus;
  bool? get isConnectionStatusSuccess => _isConnectionStatusSuccess;
  Duration? get executionDuration => _executionDuration;
  int? get affectedRows => _affectedRows;
  List<Map<String, dynamic>>? get columnMetadata => _columnMetadata;
  CancellationToken get cancellationToken => _cancellationToken;

  // Streaming getters
  bool get isStreaming => _isStreaming;
  int get rowsProcessed => _rowsProcessed;
  double get progress => _progress;

  void setQuery(String value) {
    _query = value;
    _clearError();
    notifyListeners();
  }

  Future<void> executeQuery() async {
    _clearError();
    _isLoading = true;
    _results = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      final result = await _executePlaygroundQuery(_query);
      stopwatch.stop();
      _isLoading = false;

      result.fold(
        (response) {
          if (response.error != null) {
            _error = response.error;
            _results = [];
            _columnMetadata = null;
          } else {
            _results = response.data;
            _affectedRows = response.affectedRows ?? 0;
            _columnMetadata = response.columnMetadata;
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
          _executionDuration = stopwatch.elapsed;
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
      _executionDuration = stopwatch.elapsed;
      AppLogger.error(
        'Query execution threw: ${failure.message}',
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
    _rowsProcessed = 0;
    _results = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _progress = 0.0;
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
          _progress = _rowsProcessed / (_rowsProcessed + _progressEstimateOffset);

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
        'Streaming exception: ${failure.message}',
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
    _isStreaming = false;
    _rowsProcessed = 0;
    _progress = 0.0;
    _cancellationToken.reset();
    notifyListeners();
  }

  /// Cancela a query em execução.
  void cancelQuery() {
    if (_isLoading) {
      _cancellationToken.cancel();
      unawaited(_executeStreamingQuery.cancelActiveStream());
      _isLoading = false;
      _isStreaming = false;
      _error = AppStrings.queryCancelledByUser;
      notifyListeners();
    }
  }

  void _notifyStreamingProgressIfNeeded() {
    final now = DateTime.now();
    final shouldNotify = now.difference(_lastStreamingNotifyAt) >= _streamingUiUpdateInterval;
    if (!shouldNotify) {
      return;
    }

    _lastStreamingNotifyAt = now;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }
}
