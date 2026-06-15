import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/app_environment.dart';

const String odbcUsageProfileEnvKey = 'ODBC_USAGE_PROFILE';

/// Resolves the ODBC worker/pool preset from [odbcUsageProfileEnvKey].
///
/// Only `balancedServer` and `highThroughput` are exposed for plug_agente;
/// unknown values fall back to [OdbcUsageProfile.balancedServer].
OdbcUsageProfile resolveOdbcUsageProfile({String? rawValue}) {
  final normalized = (rawValue ?? AppEnvironment.get(odbcUsageProfileEnvKey))
      ?.trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_-]+'), '');
  return switch (normalized) {
    'highthroughput' || 'high' || 'throughput' => OdbcUsageProfile.highThroughput,
    'balancedserver' || 'server' || 'balanced' || null || '' => OdbcUsageProfile.balancedServer,
    _ => OdbcUsageProfile.balancedServer,
  };
}

String odbcUsageProfileConfigName(OdbcUsageProfile profile) {
  return switch (profile) {
    OdbcUsageProfile.highThroughput => 'highThroughput',
    OdbcUsageProfile.balancedServer => 'balancedServer',
    _ => profile.name,
  };
}
