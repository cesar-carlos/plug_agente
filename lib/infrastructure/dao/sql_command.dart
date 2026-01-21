import 'driver/my_odbc.dart';
import '../config/database_type.dart';
import '../config/database_config.dart';
import 'sql_valid_command.dart';
import 'sql_type_command.dart';
import 'sql_transaction.dart';

class SqlCommand {
  final MyOdbc odbc;
  String? commandText;
  final List<SqlTypeCommand> _params = [];
  List<Map<String, dynamic>> _result = [];
  Map<String, dynamic> _currentRecord = {};

  int _currentIndex = -1;
  bool _isConnected = false;
  SqlTransaction? transaction;

  bool _useReadUncommitted = false;

  SqlCommand(DatabaseConfig config)
      : odbc = MyOdbc(
          driverName: config.driverName,
          username: config.username,
          password: config.password,
          database: config.database,
          server: config.server,
          port: config.port,
          databaseType: config.databaseType,
        ) {
    transaction = SqlTransaction(odbc);
  }

  SqlTypeCommand param(String name) {
    final sqlType = SqlTypeCommand(name);
    _params.add(sqlType);
    return sqlType;
  }

  SqlTypeCommand field(String name) {
    final sqlType = SqlTypeCommand(name);

    if (!_currentRecord.containsKey(name)) {
      return sqlType;
    }

    final value = _currentRecord[name];
    if (value == null) {
      return sqlType;
    }

    if (value is DateTime) {
      sqlType.asDate = value;
    } else if (value is int) {
      sqlType.asInt = value;
    } else if (value is double) {
      sqlType.asDouble = value;
    } else if (value is bool) {
      sqlType.asBool = value;
    } else {
      sqlType.asString = value.toString();
    }

    return sqlType;
  }

  String _substituteParameters(String query) {
    String result = query;

    if (_params.isNotEmpty) {
      for (var param in _params) {
        if (param.value == null) {
          throw Exception(
              'Parâmetro :${param.name} não foi definido ou está nulo.');
        }

        final replacement =
            param.isSingleQuote ? "'${param.value}'" : param.value.toString();

        final paramPattern = RegExp(r':\b' + RegExp.escape(param.name) + r'\b');

        if (!paramPattern.hasMatch(result)) {
          throw Exception(
              'Parâmetro :${param.name} não encontrado no commandText.');
        }

        result = result.replaceAll(paramPattern, replacement);
      }
    }

    final remainingParamPattern = RegExp(r':\w+');
    if (remainingParamPattern.hasMatch(result)) {
      final matches = remainingParamPattern.allMatches(result);
      final unmatched = matches.map((m) => m.group(0)).toSet().join(', ');
      throw Exception('Parâmetros não substituídos no commandText: $unmatched');
    }

    return result;
  }

  void enableReadUncommitted() {
    _useReadUncommitted = true;
  }

  void disableReadUncommitted() {
    _useReadUncommitted = false;
  }

  String _getReadUncommittedCommand() {
    switch (odbc.type) {
      case DatabaseType.sqlServer:
      case DatabaseType.sybaseAnywhere:
        return 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED';
      case DatabaseType.postgresql:
        return 'SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED';
    }
  }

  String _getReadCommittedCommand() {
    switch (odbc.type) {
      case DatabaseType.sqlServer:
      case DatabaseType.sybaseAnywhere:
        return 'SET TRANSACTION ISOLATION LEVEL READ COMMITTED';
      case DatabaseType.postgresql:
        return 'SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED';
    }
  }

  /// Executa uma query SELECT e carrega os resultados.
  /// IMPORTANTE: Este método NÃO inicia transação, então não bloqueia tabelas.
  /// Para evitar locks compartilhados, use enableReadUncommitted() antes de chamar open().
  Future<void> open() async {
    SqlValidCommand.validateOpen(_isConnected, commandText);

    _currentIndex = -1;
    _currentRecord = {};

    final sql = _substituteParameters(commandText!);

    try {
      if (_useReadUncommitted) {
        await odbc.execute(_getReadUncommittedCommand());
      }

      // Não inicia transação para SELECT - evita bloqueio de tabelas
      _result = await odbc.execute(sql);

      if (_useReadUncommitted) {
        await odbc.execute(_getReadCommittedCommand());
      }

      if (_result.isNotEmpty) {
        _currentIndex = 0;
        _currentRecord = Map<String, dynamic>.from(_result[_currentIndex]);
      }
    } catch (err) {
      if (_useReadUncommitted) {
        try {
          await odbc.execute(_getReadCommittedCommand());
        } catch (_) {}
      }
      rethrow;
    }
  }

  bool get eof =>
      _result.isEmpty || _currentIndex < 0 || _currentIndex >= _result.length;

  bool get isEmpty => _result.isEmpty;

  int get recordCount => _result.length;

  void next() {
    if (_result.isEmpty) return;

    if (_currentIndex < _result.length - 1) {
      _currentIndex++;
      _currentRecord = Map<String, dynamic>.from(_result[_currentIndex]);
    } else {
      _currentIndex = _result.length;
    }
  }

  void first() {
    if (_result.isNotEmpty) {
      _currentIndex = 0;
      _currentRecord = Map<String, dynamic>.from(_result[_currentIndex]);
    }
  }

  Future<void> connect() async {
    try {
      await odbc.connect();
      _isConnected = true;
    } catch (err) {
      _isConnected = false;
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      if (_isConnected) {
        await odbc.disconnect();
      }
    } finally {
      _currentIndex = -1;
      _currentRecord = {};
      _isConnected = false;
      _result.clear();
      _params.clear();
    }
  }

  void clearParams() {
    _params.clear();
  }

  Future<void> startTransaction() async {
    await transaction?.start(isSelect: false);
  }

  Future<void> commit() async {
    await transaction?.commit();
  }

  Future<void> rollback() async {
    await transaction?.rollback();
  }

  void onAutoCommit() {
    transaction?.onAutoCommit();
  }

  void offAutoCommit() {
    transaction?.offAutoCommit();
  }

  bool isTransactionOpen() {
    return transaction?.isOpen() ?? false;
  }

  Future<void> execute() async {
    SqlValidCommand.validateExecute(_isConnected, commandText);

    final sql = _substituteParameters(commandText!);

    try {
      if (transaction != null &&
          !transaction!.autoCommit &&
          !transaction!.isOpen()) {
        await transaction!.start(isSelect: false);
      }

      await odbc.execute(sql);

      await transaction?.doAutoCommit();
    } catch (err) {
      await transaction?.doAutoRollback();
      rethrow;
    }
  }
}
