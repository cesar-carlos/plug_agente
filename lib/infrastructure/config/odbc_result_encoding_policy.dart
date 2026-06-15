import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/config/odbc_balanced_columnar_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_columnar_compressed_policy.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_parser.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';

/// Returns a configured encoding when [odbcResultEncodingEnvKey] is set and
/// non-blank; otherwise `null` so callers can apply driver/profile defaults.
ResultEncoding? readExplicitOdbcResultEncoding({String? rawValue}) {
  final raw = rawValue ?? AppEnvironment.get(odbcResultEncodingEnvKey);
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return resultEncodingFromString(raw) ?? ResultEncoding.rowMajor;
}

/// Effective hub SELECT encoding: explicit env wins; SQL Anywhere stays
/// row-major; [OdbcUsageProfile.highThroughput] unlocks the profile preset
/// (columnar, optionally columnarCompressed via env); balancedServer stays
/// row-major unless [odbcResultEncodingEnvKey] is set.
ResultEncoding resolveEffectiveOdbcResultEncoding({
  DatabaseType? databaseType,
  OdbcUsageProfile? usageProfile,
  String? rawValue,
}) {
  final explicit = readExplicitOdbcResultEncoding(rawValue: rawValue);
  if (explicit != null) {
    return explicit;
  }
  if (databaseType == null || databaseType == DatabaseType.sybaseAnywhere) {
    return ResultEncoding.rowMajor;
  }
  final profile = usageProfile ?? resolveOdbcUsageProfile();
  if (profile == OdbcUsageProfile.highThroughput) {
    return resolveUsageProfileResultEncoding(profile);
  }
  if (profile == OdbcUsageProfile.balancedServer && isOdbcBalancedColumnarEnabled()) {
    return ResultEncoding.columnar;
  }
  return ResultEncoding.rowMajor;
}
