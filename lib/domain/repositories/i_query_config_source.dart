import 'package:plug_agente/domain/entities/config.dart';
import 'package:result_dart/result_dart.dart';

/// Resolves the database [Config] used to execute a query.
///
/// This is the boundary the ODBC gateway depends on so that infrastructure does
/// not reach into application services directly. Implementations decide how to
/// resolve an explicit config id versus the active/current config (metadata
/// only, since query execution never needs secrets eagerly materialized here).
abstract interface class IQueryConfigSource {
  /// Resolves the config for a query, by explicit [configId] when provided,
  /// otherwise the active/current config.
  Future<Result<Config>> resolveConfigForQuery(String? configId);

  /// Resolves the active/current config (used by paths that never carry an
  /// explicit config id, such as read-only parallel batches).
  Future<Result<Config>> resolveActiveConfig();
}
