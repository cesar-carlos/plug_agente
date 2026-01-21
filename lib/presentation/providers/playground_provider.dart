import 'package:flutter/foundation.dart';

import '../../application/use_cases/execute_playground_query.dart';
import '../../application/use_cases/test_db_connection.dart';
import '../../domain/entities/config.dart';
import '../../domain/errors/failures.dart' as domain;

class PlaygroundProvider extends ChangeNotifier {
  final ExecutePlaygroundQuery _executePlaygroundQuery;
  final TestDbConnection _testDbConnection;

  PlaygroundProvider(this._executePlaygroundQuery, this._testDbConnection);

  String _query = '';
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _error;
  String? _connectionStatus;
  DateTime? _executionTime;
  int? _affectedRows;

  String get query => _query;
  List<Map<String, dynamic>> get results => _results;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get connectionStatus => _connectionStatus;
  DateTime? get executionTime => _executionTime;
  int? get affectedRows => _affectedRows;

  void setQuery(String value) {
    _query = value;
    _clearError();
    notifyListeners();
  }

  Future<void> executeQuery() async {
    _clearError();
    _isLoading = true;
    _results = [];
    _executionTime = null;
    _affectedRows = null;
    notifyListeners();

    final result = await _executePlaygroundQuery(_query);

    _isLoading = false;

    result.fold(
      (response) {
        if (response.error != null) {
          _error = response.error!;
          _results = [];
        } else {
          _results = response.data;
          _affectedRows = response.affectedRows ?? 0;
        }
        _executionTime = DateTime.now();
      },
      (failure) {
        final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
        _error = failureMessage;
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
        final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
        _error = failureMessage;
        _connectionStatus = 'Falha na conexão';
      },
    );

    notifyListeners();
  }

  void clearResults() {
    _query = '';
    _results = [];
    _error = null;
    _executionTime = null;
    _affectedRows = null;
    _connectionStatus = null;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }
}
