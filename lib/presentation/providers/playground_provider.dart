import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/errors.dart';

class PlaygroundProvider extends ChangeNotifier {
  PlaygroundProvider(this._executePlaygroundQuery, this._testDbConnection);
  final ExecutePlaygroundQuery _executePlaygroundQuery;
  final TestDbConnection _testDbConnection;

  String _query = '';
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _error;
  String? _connectionStatus;
  Duration? _executionDuration;
  int? _affectedRows;
  List<Map<String, dynamic>>? _columnMetadata;
  final CancellationToken _cancellationToken = CancellationToken();

  // Streaming support
  bool _isStreaming = false;
  int _rowsProcessed = 0;
  double _progress = 0;

  String get query => _query;
  List<Map<String, dynamic>> get results => _results;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get connectionStatus => _connectionStatus;
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
        _error = failure.toUserMessage();
        AppLogger.error('Failed to execute query: ${_error ?? failure}');
        _columnMetadata = null;
        _executionDuration = stopwatch.elapsed;
      },
    );

    notifyListeners();
  }

  Future<void> testConnection(Config config) async {
    _clearError();
    _connectionStatus = 'Testando conexão...';
    notifyListeners();

    final result = await _testDbConnection(config.connectionString);

    result.fold(
      (_) {
        _connectionStatus = 'Conexão estabelecida com sucesso';
      },
      (failure) {
        _error = failure.toUserMessage();
        AppLogger.error('Failed to test connection: ${_error ?? failure}');
        _connectionStatus = 'Falha na conexão';
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
    _isLoading = true;
    _isStreaming = true;
    _rowsProcessed = 0;
    _results = [];
    _executionDuration = null;
    _affectedRows = null;
    _columnMetadata = null;
    _progress = 0.0;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // Este método seria implementado com ExecuteStreamingQuery
      // Por enquanto, mantemos a implementação padrão
      // TODO: Implementar streaming completo quando necessário
      await executeQuery();

      _isStreaming = false;
      _progress = 1.0;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      _isStreaming = false;
      _error = 'Erro no streaming: $e';
      notifyListeners();
    } finally {
      stopwatch.stop();
      _executionDuration = stopwatch.elapsed;
    }
  }

  void clearResults() {
    _query = '';
    _results = [];
    _error = null;
    _executionDuration = null;
    _affectedRows = null;
    _connectionStatus = null;
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
      _isLoading = false;
      _error = 'Query cancelada pelo usuário';
      notifyListeners();
    }
  }

  void _clearError() {
    _error = null;
  }
}
