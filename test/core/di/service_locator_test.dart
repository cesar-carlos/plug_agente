import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/di/service_locator.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

void main() {
  group('resolveOdbcRuntimeTuning', () {
    setUp(dotenv.clean);
    tearDown(dotenv.clean);

    test('should use persisted ODBC pool size instead of env pool default', () {
      dotenv.loadFromString(envString: 'ODBC_POOL_SIZE=2');
      final settings = MockOdbcConnectionSettings(poolSize: 7);

      final tuning = resolveOdbcRuntimeTuning(
        settings: settings,
        processorCount: 4,
      );

      expect(tuning.poolSize, 7);
      expect(tuning.processorCount, 4);
      expect(tuning.asyncWorkerCount, 4);
      expect(tuning.asyncMaxPendingRequests, 28);
    });
  });
}
