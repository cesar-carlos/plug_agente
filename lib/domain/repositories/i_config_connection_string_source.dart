import 'package:plug_agente/domain/entities/config.dart';

abstract interface class IConfigConnectionStringSource {
  String generateConnectionString(Config config);

  String generateConnectionStringForPersistence(Config config);

  /// Resolves the runtime ODBC connection string for [config].
  ///
  /// Prefers the persisted connection string and injects secure credentials when
  /// needed; otherwise builds from structured fields.
  String resolveConnectionString(Config config);
}
