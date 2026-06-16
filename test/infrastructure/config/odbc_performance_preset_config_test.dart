import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/infrastructure/config/odbc_performance_preset_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_policy.dart';
import 'package:plug_agente/infrastructure/config/odbc_stream_columnar_wire_config.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';

bool _hasPlatformEnv(String key) {
  final value = Platform.environment[key]?.trim();
  return value != null && value.isNotEmpty;
}

void main() {
  setUp(() {
    dotenv.clean();
  });

  test('aggressive preset seeds high-throughput ODBC flags when unset', () {
    dotenv.loadFromString(envString: 'ODBC_PERFORMANCE_PRESET=aggressive');

    applyOdbcPerformancePresetFromEnvironment();

    expect(resolveOdbcUsageProfile(), OdbcUsageProfile.highThroughput);
    expect(isOdbcStreamColumnarWireEnabled(), isTrue);
    expect(
      resolveEffectiveOdbcResultEncoding(usageProfile: OdbcUsageProfile.highThroughput),
      ResultEncoding.columnarCompressed,
    );
    if (!_hasPlatformEnv('AGENT_STREAM_PULL_WINDOW_RECOMMENDED')) {
      expect(AppEnvironment.get('AGENT_STREAM_PULL_WINDOW_RECOMMENDED'), '16');
      expect(dotenv.env['AGENT_STREAM_PULL_WINDOW_RECOMMENDED'], '16');
    } else {
      expect(
        dotenv.env['AGENT_STREAM_PULL_WINDOW_RECOMMENDED'],
        isNull,
        reason: 'preset must not write dotenv when Platform.environment already defines the key',
      );
    }
    if (!_hasPlatformEnv('ODBC_STREAMING_CONNECT_REUSE_ENABLED')) {
      expect(AppEnvironment.get('ODBC_STREAMING_CONNECT_REUSE_ENABLED'), '1');
      expect(dotenv.env['ODBC_STREAMING_CONNECT_REUSE_ENABLED'], '1');
    } else {
      expect(dotenv.env['ODBC_STREAMING_CONNECT_REUSE_ENABLED'], isNull);
    }
  });

  test('aggressive preset does not override explicit env values', () {
    dotenv.loadFromString(
      envString: 'ODBC_PERFORMANCE_PRESET=aggressive\nODBC_USAGE_PROFILE=balancedServer',
    );

    applyOdbcPerformancePresetFromEnvironment();

    expect(resolveOdbcUsageProfile(), OdbcUsageProfile.balancedServer);
  });
}
