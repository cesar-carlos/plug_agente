import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/infrastructure/builders/odbc_connection_builder.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';

/// Resolves and rewrites ODBC connection strings for query execution.
///
/// Extracted from `OdbcDatabaseGateway` to keep connection-string composition
/// (database override handling, dialect-specific key replacement) isolated and
/// unit-testable. All methods are pure.
final class OdbcConnectionStringRewriter {
  OdbcConnectionStringRewriter._();

  static final List<RegExp> _databaseKeyPatterns = [
    RegExp(r'(database)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(dbn)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(initial\s+catalog)\s*=\s*[^;]*', caseSensitive: false),
  ];

  /// Resolves the effective connection string for [config], optionally
  /// overriding the target database with [databaseOverride].
  static String resolve(
    Config config,
    DatabaseConfig databaseConfig, {
    String? databaseOverride,
  }) {
    final override = databaseOverride?.trim();
    final resolved = config.resolveConnectionString().trim();

    if (override != null && override.isNotEmpty) {
      final overriddenDatabaseConfig = DatabaseConfig(
        driverName: databaseConfig.driverName,
        username: databaseConfig.username,
        password: databaseConfig.password,
        database: override,
        server: databaseConfig.server,
        port: databaseConfig.port,
        databaseType: databaseConfig.databaseType,
      );
      if (resolved.isNotEmpty) {
        return overrideDatabase(resolved, override);
      }
      return OdbcConnectionBuilder.build(overriddenDatabaseConfig);
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }
    return OdbcConnectionBuilder.build(databaseConfig);
  }

  /// Replaces the database key in [connectionString] with [database], or
  /// appends a `DATABASE=` clause when no recognizable key is present.
  static String overrideDatabase(
    String connectionString,
    String database,
  ) {
    var updated = connectionString;

    var replaced = false;
    for (final pattern in _databaseKeyPatterns) {
      if (pattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(pattern, (match) {
          replaced = true;
          return '${match.group(1)}=$database';
        });
      }
    }

    if (replaced) {
      return updated;
    }

    final suffix = updated.endsWith(';') ? '' : ';';
    return '$updated${suffix}DATABASE=$database';
  }
}
