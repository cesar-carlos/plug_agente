import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

/// Pool de conexões ODBC reutilizáveis.
///
/// Mantém conexões ativas para reutilização, reduzindo o overhead
/// de criar novas conexões para cada query.
class OdbcConnectionPool implements IConnectionPool {
  // connectionId -> Connection

  OdbcConnectionPool(this._service);
  final OdbcService _service;
  final Map<String, String> _pool = {}; // connectionString -> connectionId
  final Map<String, int> _refCount = {}; // connectionId -> count
  final Map<String, Connection> _connections = {};

  /// Helper para converter erros ODBC em String.
  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  @override
  Future<Result<String>> acquire(String connectionString) async {
    // Reutilizar conexão existente
    if (_pool.containsKey(connectionString)) {
      final connId = _pool[connectionString]!;
      _refCount[connId] = (_refCount[connId] ?? 0) + 1;
      return Success(connId);
    }

    // Criar nova conexão
    final result = await _service.connect(connectionString);
    return result.fold(
      (conn) {
        _pool[connectionString] = conn.id;
        _refCount[conn.id] = 1;
        _connections[conn.id] = conn;
        return Success(conn.id);
      },
      (error) => Failure(
        domain.ConnectionFailure(
          'Failed to create connection: ${_odbcErrorMessage(error)}',
        ),
      ),
    );
  }

  @override
  Future<Result<void>> release(String connectionId) async {
    if (!_refCount.containsKey(connectionId)) {
      return Failure(
        domain.ConnectionFailure('Connection not found in pool: $connectionId'),
      );
    }

    _refCount[connectionId] = _refCount[connectionId]! - 1;

    // Manter conexão viva para reuso (não desconectar)
    return const Success(unit);
  }

  @override
  Future<Result<void>> closeAll() async {
    final errors = <String>[];

    for (final connId in _pool.values) {
      final result = await _service.disconnect(connId);
      result.fold((_) {}, (error) => errors.add(_odbcErrorMessage(error)));
    }

    _pool.clear();
    _refCount.clear();
    _connections.clear();

    if (errors.isNotEmpty) {
      return Failure(
        domain.ConnectionFailure('Errors closing pool: ${errors.join(', ')}'),
      );
    }
    return const Success(unit);
  }

  @override
  Future<Result<int>> getActiveCount() async {
    return Success(_pool.length);
  }

  /// Verifica se uma conexão está ativa no pool.
  bool hasConnection(String connectionString) {
    return _pool.containsKey(connectionString);
  }

  /// Retorna o número de referências ativas para uma conexão.
  int? getReferenceCount(String connectionId) {
    return _refCount[connectionId];
  }
}
