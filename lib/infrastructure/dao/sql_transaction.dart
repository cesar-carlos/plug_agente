import 'driver/my_odbc.dart';

class SqlTransaction {
  bool _autoCommit = true;
  bool _isOpen = false;
  final MyOdbc _connection;

  SqlTransaction(this._connection);

  void onAutoCommit() {
    _autoCommit = true;
  }

  void offAutoCommit() {
    _autoCommit = false;
  }

  bool get autoCommit => _autoCommit;

  bool isOpen() {
    return _isOpen;
  }

  Future<void> start({bool isSelect = false}) async {
    if (isSelect) {
      return;
    }

    if (!_isOpen) {
      _isOpen = true;
      await _connection.startTransaction();
    }
  }

  Future<void> commit() async {
    await _connection.commitTransaction();
    _isOpen = false;
  }

  Future<void> rollback() async {
    await _connection.rollbackTransaction();
    _isOpen = false;
  }

  Future<void> doAutoCommit() async {
    if (_autoCommit && _isOpen) {
      await _connection.commitTransaction();
      _isOpen = false;
    }
  }

  Future<void> doAutoRollback() async {
    if (_autoCommit && _isOpen) {
      await _connection.rollbackTransaction();
      _isOpen = false;
    }
  }
}
