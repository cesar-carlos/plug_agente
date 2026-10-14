import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/source_discovery.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/infrastructure/external_services/sql_operation_connection_string.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

/// Only fixed metadata SELECTs; no caller SQL, business rows, retries or DDL.
class OdbcSourceDiscovery implements ISourceDiscoveryProbe {
  const OdbcSourceDiscovery(this.service, this.connections, this.limiter);
  final odbc.OdbcService service;
  final IConfigConnectionStringSource connections;
  final DirectOdbcConnectionLimiter limiter;

  @override
  Future<Result<SourceDiscovery>> inspect(Config config, String database) => withConnection(
    config,
    database,
    (id, _) => inspectConnection(service, id, config, database),
  );

  /// Dedicated session, no reconnect/retry. Native work must settle before cleanup.
  Future<Result<T>> withConnection<T extends Object>(
    Config config,
    String database,
    Future<T> Function(String id, Duration Function() remaining) action, {
    Duration timeout = const Duration(seconds: 15),
    int maxResultBufferBytes = 16384,
  }) async {
    final watch = Stopwatch()..start();
    DirectOdbcConnectionLease? lease;
    String? id;
    Future<Object?>? pending;
    var lateConnect = false;
    var budgetExpired = false;
    Duration remaining() {
      final value = timeout - watch.elapsed;
      if (budgetExpired || value <= Duration.zero) throw TimeoutException('Discovery budget exhausted');
      return value;
    }

    Future<V> tracked<V>(Future<V> action) async {
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
      } on TimeoutException {
        // Timer completion is authoritative even if the stopwatch is short of the deadline.
        budgetExpired = true;
        rethrow;
      } finally {
        if (settled) pending = null;
      }
    }

    Future<void> close(String connectionId) async {
      (await service.disconnect(connectionId)).getOrThrow();
    }

    Future<void> cleanup(String connectionId, DirectOdbcConnectionLease? held) async {
      try {
        await close(connectionId);
        held?.release();
      } on Object {
        // Keep admission reserved when the native connection may still be open.
        AppLogger.warning('Source discovery connection cleanup failed; admission remains reserved.');
      }
    }

    try {
      lease = (await limiter.acquire(operation: 'batch_transaction', acquireTimeout: remaining())).getOrThrow();
      final connection = service.connect(
        SqlOperationConnectionString.bindDatabase(connections.resolveConnectionString(config), database),
        options: odbc.ConnectionOptions(
          loginTimeout: remaining(),
          queryTimeout: remaining(),
          maxResultBufferBytes: maxResultBufferBytes,
          maxReconnectAttempts: 0,
        ),
      );
      try {
        id = (await connection.timeout(remaining())).getOrThrow().id;
      } on TimeoutException {
        lateConnect = true;
        final held = lease;
        unawaited(
          connection.then(
            (result) async {
              if (result.isSuccess()) {
                await cleanup(result.getOrThrow().id, held);
              } else {
                held.release();
              }
            },
            onError: (Object _) => held.release(),
          ),
        );
        rethrow;
      }
      return Success(await tracked(action(id, remaining)));
    } on Object catch (error) {
      if (error is domain.Failure) return Failure(error);
      return Failure(
        domain.DatabaseFailure.withContext(
          code: 'SOURCE_DISCOVERY_UNAVAILABLE',
          message: 'Live source identity could not be verified.',
          cause: error,
          context: const {'retryable': false},
        ),
      );
    } finally {
      watch.stop();
      if (!lateConnect) {
        if (id == null) {
          lease?.release();
        } else {
          final connectionId = id;
          final held = lease;
          // Await native completion before disconnect/releasing admission on timeout.
          unawaited((pending ?? Future<Object?>.value()).then((_) => cleanup(connectionId, held)));
        }
      }
    }
  }

  static String dialectFor(odbc.DbmsInfo info) => switch (info.engineId) {
    'postgres' => 'postgres',
    'sqlserver' => 'mssql',
    'sybase_asa' => 'sybase',
    _ when info.dbmsName.toLowerCase().contains('firebird') => 'firebird',
    _ => throw domain.DatabaseFailure.withContext(
      code: 'SOURCE_DIALECT_UNSUPPORTED',
      message: 'Database engine is unsupported.',
    ),
  };

  static String metadataSql(String dialect) => switch (dialect) {
    'postgres' =>
      'SELECT current_database() AS db, c.system_identifier::text AS cluster_id, d.oid::text AS db_id FROM pg_control_system() c CROSS JOIN pg_database d WHERE d.datname = current_database()',
    'mssql' =>
      "SELECT DB_NAME() AS db, CONVERT(varchar(128),SERVERPROPERTY('MachineName')) AS machine, CONVERT(varchar(128),SERVERPROPERTY('ServerName')) AS instance, CONVERT(varchar(36),database_guid) AS db_guid, CONVERT(varchar(36),recovery_fork_guid) AS fork_guid FROM sys.database_recovery_status WHERE database_id = DB_ID()",
    'firebird' => r'SELECT MON$DATABASE_NAME AS db, MON$GUID AS db_guid, MON$FILE_ID AS file_id FROM MON$DATABASE',
    // Explicit DBA provisioning only. Runtime never creates or repairs this marker.
    'sybase' =>
      'SELECT DB_NAME() AS db, database_uuid, CAST(version AS VARCHAR(10)) AS identity_version FROM "DBA"."se7e_source_identity"',
    _ => throw ArgumentError('Unsupported dialect'),
  };

  static Future<SourceDiscovery> inspectConnection(
    odbc.OdbcService service,
    String id,
    Config config,
    String database,
  ) async {
    final info = (await service.getConnectionDbmsInfo(id)).getOrThrow();
    final dialect = dialectFor(info);
    final metadata = await service.executeQueryNamed(id, metadataSql(dialect), const {});
    if (metadata.isError()) {
      throw domain.DatabaseFailure.withContext(
        code: 'SOURCE_IDENTITY_UNAVAILABLE',
        message: 'Source identity metadata is unavailable. Verify provisioning and metadata permissions.',
        context: const {'retryable': false},
      );
    }
    final result = metadata.getOrThrow();
    final expected = switch (dialect) {
      'postgres' => 3,
      'mssql' => 5,
      _ => 3,
    };
    if (result.rowCount != 1 ||
        result.rows.length != 1 ||
        result.columns.length != expected ||
        result.rows.single.length != expected ||
        result.additionalResults.isNotEmpty ||
        result.refCursorResults.isNotEmpty) {
      throw domain.DatabaseFailure.withContext(
        code: 'SOURCE_IDENTITY_INCOMPLETE',
        message: 'Complete source metadata is required.',
      );
    }
    final values = result.rows.single.map((v) {
      if (v is! String || v.trim().isEmpty || v.length > 2048) {
        throw domain.DatabaseFailure.withContext(
          code: 'SOURCE_IDENTITY_INCOMPLETE',
          message: 'Source identity metadata is missing.',
        );
      }
      return v.trim();
    }).toList();
    if (dialect == 'sybase' &&
        (values[2] != '1' ||
            !RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$').hasMatch(values[1]))) {
      throw domain.DatabaseFailure.withContext(
        code: 'SOURCE_IDENTITY_INCOMPLETE',
        message: 'A valid, explicitly provisioned SQL Anywhere source identity is required.',
      );
    }
    String canonical(String value) => dialect == 'firebird' && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)
        ? value.replaceAll(r'\', '/').toLowerCase()
        : value;
    if (canonical(values.first) != canonical(database)) {
      throw domain.DatabaseFailure.withContext(
        code: 'SOURCE_DATABASE_MISMATCH',
        message: 'Live connection selected another database.',
      );
    }
    final hash = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              if (dialect == 'sybase') 'source-discovery-provisioned-v1' else 'source-discovery-v1',
              dialect,
              config.host.toLowerCase(),
              config.port,
              ...values.map(canonical),
            ]),
          ),
        )
        .toString();
    return SourceDiscovery(
      database: database,
      dialect: dialect,
      identityHash: hash,
      identityKind: dialect == 'sybase' ? 'provisioned' : 'native',
      engineVersion: info.dbmsVersion,
    );
  }
}
