import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/config/odbc_balanced_columnar_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_columnar_compressed_policy.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_stream_columnar_wire_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_stream_wire_only_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';

const String odbcPerformancePresetEnvKey = 'ODBC_PERFORMANCE_PRESET';

/// Applies performance preset env overrides before ODBC profile / wire flags
/// are resolved. Explicit per-flag env values always win.
void applyOdbcPerformancePresetFromEnvironment() {
  final preset = AppEnvironment.get(odbcPerformancePresetEnvKey)?.trim().toLowerCase();
  if (preset == null || preset.isEmpty || preset != 'aggressive') {
    return;
  }

  _setEnvIfUnset(odbcUsageProfileEnvKey, 'highThroughput');
  _setEnvIfUnset(odbcBalancedColumnarEnvKey, '1');
  _setEnvIfUnset(odbcHighThroughputCompressedEnvKey, '1');
  _setEnvIfUnset(odbcStreamColumnarWireEnvKey, '1');
  _setEnvIfUnset(odbcStreamWireOnlyEnvKey, '1');
  _setEnvIfUnset(odbcResultEncodingEnvKey, 'columnarCompressed');
}

void _setEnvIfUnset(String key, String value) {
  final existing = AppEnvironment.get(key);
  if (existing != null && existing.trim().isNotEmpty) {
    return;
  }
  dotenv.env[key] = value;
}
