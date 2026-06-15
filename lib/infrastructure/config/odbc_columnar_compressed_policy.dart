import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/app_environment.dart';

const String odbcHighThroughputCompressedEnvKey = 'ODBC_HIGH_THROUGHPUT_COMPRESSED';
const String odbcPreferColumnarCompressedEnvKey = 'ODBC_PREFER_COLUMNAR_COMPRESSED';

bool _isTruthyEnv(String? raw) {
  final normalized = raw?.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

/// When true, [OdbcUsageProfile.highThroughput] may upgrade columnar to
/// [ResultEncoding.columnarCompressed] for hub-bound SELECT workloads.
bool preferColumnarCompressedForHighThroughput({String? rawValue}) {
  final explicit = rawValue ?? AppEnvironment.get(odbcHighThroughputCompressedEnvKey);
  if (explicit != null && explicit.trim().isNotEmpty) {
    return _isTruthyEnv(explicit);
  }
  return _isTruthyEnv(AppEnvironment.get(odbcPreferColumnarCompressedEnvKey));
}

/// Profile default before SQL Anywhere / balancedServer row-major overrides.
ResultEncoding resolveUsageProfileResultEncoding(OdbcUsageProfile profile) {
  final recommended = ResolvedOdbcUsageProfile.fromUsageProfile(profile).recommendedResultEncoding;
  if (profile == OdbcUsageProfile.highThroughput &&
      recommended == ResultEncoding.columnar &&
      preferColumnarCompressedForHighThroughput()) {
    return ResultEncoding.columnarCompressed;
  }
  return recommended;
}
