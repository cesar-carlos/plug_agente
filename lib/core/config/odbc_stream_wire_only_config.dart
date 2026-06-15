import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/odbc_stream_columnar_wire_config.dart';

const String odbcStreamWireOnlyEnvKey = 'ODBC_STREAM_WIRE_ONLY';

bool _isTruthyEnv(String? raw) {
  final normalized = raw?.trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

bool isOdbcStreamWireOnlyNegotiated(Map<String, dynamic>? negotiatedExtensions) {
  final raw = negotiatedExtensions?['columnarWireOnly'];
  if (raw is bool) {
    return raw;
  }
  if (raw is String) {
    return _isTruthyEnv(raw);
  }
  return false;
}

/// When true with [isOdbcStreamColumnarWireEnabled], Hub chunks omit row-map
/// materialization and send typed columnar payloads only.
bool resolveOdbcStreamWireOnlyEnabled({
  Map<String, dynamic>? negotiatedExtensions,
  String? rawValue,
}) {
  if (!isOdbcStreamColumnarWireEnabled()) {
    return false;
  }
  final explicit = rawValue ?? AppEnvironment.get(odbcStreamWireOnlyEnvKey);
  if (explicit != null && explicit.trim().isNotEmpty) {
    return _isTruthyEnv(explicit);
  }
  return isOdbcStreamWireOnlyNegotiated(negotiatedExtensions);
}
