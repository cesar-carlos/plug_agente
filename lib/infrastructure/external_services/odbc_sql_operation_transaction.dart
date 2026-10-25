import 'dart:async';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/utils/sql_text_scanner.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_transaction.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_schema.dart';
import 'package:plug_agente/infrastructure/external_services/sql_operation_connection_string.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

class OdbcSqlOperationTransactionFactory implements ISqlOperationTransactionFactory {
  const OdbcSqlOperationTransactionFactory(this._service, this._connections, this._limiter);
  final odbc.OdbcService _service;
  final IConfigConnectionStringSource _connections;
  final DirectOdbcConnectionLimiter _limiter;
  @override
  Future<Result<ISqlOperationTransaction>> open(
    SqlOperationTarget target,
    Duration timeout, {
    SqlOperationPlan? plan,
  }) async {
    final watch = Stopwatch()..start();
    DirectOdbcConnectionLease? lease;
    String? connectionId;
    var lateConnectOwnsLease = false;
    Future<Object?>? pending;
    Duration remaining() {
      final result = timeout - watch.elapsed;
      if (result <= Duration.zero) throw TimeoutException('Operation connection budget exhausted');
      return result;
    }

    Future<T> tracked<T>(Future<T> Function() start) async {
      remaining();
      final action = start();
      var settled = false;
      pending = action.then<Object?>(
        (_) {
          settled = true;
          return null;
        },
        onError: (Object _) {
          settled = true;
          return null;
        },
      );
      try {
        return await action.timeout(remaining());
      } finally {
        if (settled) pending = null;
      }
    }

    try {
      lease = (await _limiter.acquire(operation: 'batch_transaction', acquireTimeout: remaining())).getOrThrow();
      final connectionString = SqlOperationConnectionString.bindDatabase(
        _connections.resolveConnectionString(target.config),
        target.database,
      );
      final budget = remaining();
      final connecting = _service.connect(
        connectionString,
        options: odbc.ConnectionOptions(
          loginTimeout: budget,
          queryTimeout: budget,
          maxResultBufferBytes: 16 * 1024 * 1024,
          maxReconnectAttempts: 0,
        ),
      );
      try {
        connectionId = (await connecting.timeout(remaining())).getOrThrow().id;
      } on TimeoutException {
        lateConnectOwnsLease = true;
        final lateLease = lease;
        unawaited(
          connecting.then(
            (result) async {
              try {
                final connection = result.getOrNull();
                if (connection != null) await _disconnect(_service, connection.id);
              } finally {
                lateLease.release();
              }
            },
            onError: (Object _) {
              lateLease.release();
            },
          ),
        );
        rethrow;
      }
      final info = (await tracked(() => _service.getConnectionDbmsInfo(connectionId!))).getOrThrow();
      final engine = switch (info.engineId) {
        'postgres' => 'postgres',
        'sqlserver' => 'mssql',
        'sybase_asa' => 'sybase',
        _ => throw _failure('SQL_OPERATION_CAPABILITY_UNAVAILABLE', 'Database engine is not supported.'),
      };
      if (plan != null && plan.nativeStatementCount(engine) > 32) {
        throw _failure(
          'SQL_OPERATION_STEP_LIMIT',
          'Identity, structure and row-count checks exceed the 32-statement budget.',
        );
      }
      if (plan?.expectedStructure != null && target.expectedSource == null) {
        throw _failure(
          'SQL_OPERATION_CAPABILITY_UNAVAILABLE',
          'Structural verification requires executing-source identity.',
        );
      }
      if (!info.capabilities.supportsPreparedStatements) {
        throw _failure('SQL_OPERATION_CAPABILITY_UNAVAILABLE', 'Typed prepared parameters are required.');
      }
      if (target.expectedSource != null) {
        final proof = await tracked(
          () => OdbcSourceDiscovery.inspectConnection(_service, connectionId!, target.config, target.database),
        );
        target.expectedSource!.verify(proof);
      } else {
        // SQL_ATTR_CURRENT_CATALOG is empty/truncated on supported native
        // drivers (including Unicode psqlODBC). Never authorize from that hint.
        final metadataSql = switch (engine) {
          'postgres' => 'SELECT CURRENT_DATABASE() AS operation_database',
          'firebird' => r'SELECT MON$DATABASE_NAME AS operation_database FROM MON$DATABASE',
          _ => 'SELECT DB_NAME() AS operation_database',
        };
        final proof = (await tracked(
          () => _service.executeQueryNamed(connectionId!, metadataSql, const {}),
        )).getOrThrow();
        if (proof.columns.length != 1 ||
            proof.rows.length != 1 ||
            proof.rows.single.length != 1 ||
            proof.rowCount != 1 ||
            proof.additionalResults.isNotEmpty ||
            proof.refCursorResults.isNotEmpty ||
            proof.rows.single.single is! String) {
          throw _failure('SQL_OPERATION_SOURCE_MISMATCH', 'Live database identity cannot be proven.');
        }
        final catalog = (proof.rows.single.single! as String).trim();
        // Only Windows absolute Firebird paths are case insensitive; remote Unix
        // paths and database names retain their exact identity. Aliases fail closed.
        String identity(String value) => engine == 'firebird' && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)
            ? value.replaceAll(r'\', '/').toLowerCase()
            : value;
        if (catalog.isEmpty || identity(catalog) != identity(target.database)) {
          throw _failure('SQL_OPERATION_SOURCE_MISMATCH', 'Live connection selected a different database.');
        }
      }
      if (plan?.expectedStructure case final structure?) {
        final discovery = OdbcSourceDiscovery(_service, _connections, _limiter);
        await tracked(
          () => OdbcSourceSchema(discovery).verifyColumns(connectionId!, structure, engine, remaining),
        );
        // The structure proof and the identity bracketing it use this same connection.
        final proof = await tracked(
          () => OdbcSourceDiscovery.inspectConnection(_service, connectionId!, target.config, target.database),
        );
        target.expectedSource!.verify(proof);
        remaining();
      }
      // Do not retry begin with weaker options when the driver refuses them.
      final transactionId = (await tracked(
        () => _service.beginTransaction(connectionId!, accessMode: odbc.TransactionAccessMode.readWrite),
      )).getOrThrow();
      return Success(_OdbcSqlOperationTransaction(_service, connectionId, transactionId, engine, lease));
    } on Object catch (error) {
      if (!lateConnectOwnsLease) {
        if (connectionId != null) {
          final id = connectionId;
          final waiting = pending;
          final closing = waiting == null ? _disconnect(_service, id) : waiting.then((_) => _disconnect(_service, id));
          final heldLease = lease;
          unawaited(closing.then((_) => heldLease?.release(), onError: (Object _) => heldLease?.release()));
        } else {
          lease?.release();
        }
      }
      return Failure(_nativeFailure(error, 'open'));
    } finally {
      watch.stop();
    }
  }
}

class _OdbcSqlOperationTransaction implements ISqlOperationTransaction {
  _OdbcSqlOperationTransaction(this._service, this._connectionId, this._transactionId, this._engine, this._lease);
  final odbc.OdbcService _service;
  final String _connectionId;
  final int _transactionId;
  final String _engine;
  final DirectOdbcConnectionLease _lease;
  bool _closed = false;
  bool _completionStarted = false;
  Future<Object?>? _pendingNative;
  Future<T> _call<T>(Future<T> Function() start, Duration timeout) async {
    if (_closed || _completionStarted || _pendingNative != null) {
      throw _failure('SQL_OPERATION_NATIVE_BUSY', 'Native session is not reusable.');
    }
    if (timeout <= Duration.zero) {
      throw SqlOperationFailure(
        code: 'SQL_OPERATION_NATIVE_FAILED',
        message: 'Native SQL operation deadline expired before dispatch.',
        context: const {'execution_not_started': true, 'outcome_unknown': false, 'retryable': false},
      );
    }
    final action = start();
    var settled = false;
    _pendingNative = action.then<Object?>(
      (_) {
        settled = true;
        return null;
      },
      onError: (Object _) {
        settled = true;
        return null;
      },
    );
    try {
      return await action.timeout(timeout);
    } finally {
      if (settled) _pendingNative = null;
    }
  }

  @override
  Result<void> validatePlan(SqlOperationPlan plan) {
    final statements = plan.nativeStatementCount(_engine);
    if (statements > 32) {
      return Failure(
        _failure('SQL_OPERATION_STEP_LIMIT', 'Native row-count queries also count toward the 32-statement limit.'),
      );
    }
    if ({'postgres', 'firebird'}.contains(_engine) &&
        plan.steps.any(
          (s) => s.effect != SqlOperationEffect.select && !_hasReturning(s.sql),
        )) {
      return Failure(
        _failure('SQL_OPERATION_CAPABILITY_UNAVAILABLE', 'Every write on this engine requires RETURNING.'),
      );
    }
    return const Success(unit);
  }

  @override
  Future<Result<SqlOperationStepResult>> execute(
    SqlOperationStep step,
    Map<String, SqlScalar> parameters,
    Duration timeout,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final write = step.effect != SqlOperationEffect.select;
      if (write && {'postgres', 'firebird'}.contains(_engine) && !_hasReturning(step.sql)) {
        throw _failure(
          'SQL_OPERATION_CAPABILITY_UNAVAILABLE',
          'This engine requires RETURNING to prove direct affected rows.',
        );
      }
      final params = {for (final e in parameters.entries) e.key: _parameter(e.value)};
      final result = (await _call(
        () => _service.executeQueryNamed(_connectionId, step.sql, params),
        timeout,
      )).getOrThrow();
      if (result.additionalResults.isNotEmpty ||
          result.refCursorResults.isNotEmpty ||
          result.columns.toSet().length != result.columns.length ||
          result.rows.any((r) => r.length != result.columns.length)) {
        throw _failure(
          'SQL_OPERATION_RESULT_UNSUPPORTED',
          'Ambiguous or multiple native results cannot prove operation conditions.',
        );
      }
      int? affected;
      if (write) {
        if (_engine == 'mssql' || _engine == 'sybase') {
          final remaining = timeout - watch.elapsed;
          if (remaining <= Duration.zero) throw TimeoutException('Affected-row verification budget exhausted');
          // Fixed metadata query on the same connection, immediately after DML, never caller SQL.
          final count = (await _call(
            () => _service.executeQueryNamed(_connectionId, 'SELECT @@ROWCOUNT AS operation_affected_rows', const {}),
            remaining,
          )).getOrThrow();
          if (count.rows.length == 1 && count.rows.single.length == 1) {
            final value = count.rows.single.single;
            affected = value is int
                ? value
                : value is String
                ? int.tryParse(value)
                : null;
          }
        } else {
          if (result.columns.isEmpty || result.rowCount != result.rows.length) {
            throw _failure('SQL_OPERATION_ROW_COUNT_UNKNOWN', 'RETURNING result is not complete.');
          }
          affected = result.rows.length;
        }
      } else if (result.rowCount != result.rows.length) {
        throw _failure('SQL_OPERATION_RESULT_INCOMPLETE', 'Read condition requires complete rows.');
      }
      return Success(
        SqlOperationStepResult(
          rows: [
            for (final row in result.rows) {for (var i = 0; i < result.columns.length; i++) result.columns[i]: row[i]},
          ],
          directlyAffectedRows: affected,
        ),
      );
    } on Object catch (error) {
      return Failure(_nativeFailure(error, 'execute'));
    } finally {
      watch.stop();
    }
  }

  @override
  Future<Result<void>> commit(Duration timeout) =>
      _complete(() => _service.commitTransaction(_connectionId, _transactionId), timeout, 'commit');
  @override
  Future<Result<void>> rollback(Duration timeout) =>
      _complete(() => _service.rollbackTransaction(_connectionId, _transactionId), timeout, 'rollback');
  Future<Result<void>> _complete(Future<Result<void>> Function() action, Duration timeout, String stage) async {
    try {
      (await _call(() {
        _completionStarted = true;
        return action();
      }, timeout)).getOrThrow();
      return const Success(unit);
    } on Object catch (error) {
      return Failure(_nativeFailure(error, stage));
    }
  }

  @override
  Future<Result<void>> close() async {
    if (_closed) return const Success(unit);
    _closed = true;
    final waiting = _pendingNative;
    final closing = waiting == null
        ? _disconnect(_service, _connectionId)
        : waiting.then((_) => _disconnect(_service, _connectionId));
    // A late cleanup retains its admission slot until the real native future settles.
    unawaited(closing.then((_) => _lease.release(), onError: (Object _) => _lease.release()));
    try {
      if (waiting != null) {
        return Failure(
          _failure('SQL_OPERATION_CLEANUP_PENDING', 'Cleanup awaits native completion; connection is quarantined.'),
        );
      }
      (await closing.timeout(const Duration(seconds: 15))).getOrThrow();
      return const Success(unit);
    } on Object catch (error) {
      return Failure(_nativeFailure(error, 'close'));
    }
  }

  static Object? _parameter(SqlScalar scalar) => switch (scalar.type) {
    SqlScalarType.integer => odbc.ParamValueInt64(int.parse(scalar.value! as String)),
    SqlScalarType.decimal => odbc.ParamValueDecimal(scalar.value! as String),
    SqlScalarType.nullValue => const odbc.ParamValueNull(),
    SqlScalarType.boolean => scalar.value,
    _ => odbc.ParamValueString(scalar.value! as String),
  };
}

SqlOperationFailure _failure(String code, String message) => SqlOperationFailure(code: code, message: message);
SqlOperationFailure _nativeFailure(Object error, String stage) => error is SqlOperationFailure
    ? error
    : stage == 'open' &&
          error is domain.Failure &&
          {'SOURCE_IDENTITY_MISMATCH', 'SOURCE_STRUCTURE_MISMATCH'}.contains(error.code)
    ? SqlOperationFailure(
        code: error.code,
        message: error.message,
        context: const {'stage': 'open', 'retryable': false, 'outcome_unknown': false},
      )
    : SqlOperationFailure(
        code: 'SQL_OPERATION_NATIVE_FAILED',
        message: 'Native SQL operation $stage failed.',
        context: {
          'stage': stage,
          'retryable': false,
          'outcome_unknown': error is TimeoutException || OdbcErrorInspector.outcomeUnknown(error),
        },
      );

bool _hasReturning(String sql) {
  final code = StringBuffer();
  scanSqlText(
    sql,
    onCode: (start, end) => code.write(sql.substring(start, end)),
    onLiteral: (start, end) => code.write(' '),
    onComment: (start, end, {required isBlock}) => code.write(' '),
  );
  return RegExp(r'\breturning\b', caseSensitive: false).hasMatch(code.toString());
}

Future<Result<void>> _disconnect(odbc.OdbcService service, String connectionId) async {
  try {
    (await service.disconnect(connectionId)).getOrThrow();
    return const Success(unit);
  } on Object catch (error) {
    return Failure(_nativeFailure(error, 'close'));
  }
}
