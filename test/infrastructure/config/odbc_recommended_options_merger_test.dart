import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';

void main() {
  group('OdbcRecommendedOptionsMerger.mergeConnectionOptions', () {
    test('propagates profile stream/block/sqlPointer fields and prefers plug buffers', () {
      const plug = ConnectionAcquireOptions(
        loginTimeout: Duration(seconds: 12),
        queryTimeout: Duration(seconds: 34),
        maxResultBufferBytes: 8 * 1024 * 1024,
        initialResultBufferBytes: 128 * 1024,
        autoReconnectOnConnectionLost: false,
        maxReconnectAttempts: 2,
        reconnectBackoff: Duration(milliseconds: 250),
      );
      const recommended = odbc.ConnectionOptions(
        connectionTimeout: Duration(seconds: 9),
        loginTimeout: Duration(seconds: 99),
        queryTimeout: Duration(seconds: 99),
        maxResultBufferBytes: 1,
        initialResultBufferBytes: 1,
        streamChunkSizeBytes: 1024 * 1024,
        blockFetchBatchSize: 512,
        sqlPointerCacheMaxSize: 128,
        slowQueryThreshold: Duration(seconds: 5),
        autoReconnectOnConnectionLost: true,
        maxReconnectAttempts: 9,
        reconnectBackoff: Duration(seconds: 3),
      );

      final merged = OdbcRecommendedOptionsMerger.mergeConnectionOptions(
        plugOptions: plug,
        recommended: recommended,
        lazyStrings: true,
      );

      expect(merged.connectionTimeout, recommended.connectionTimeout);
      expect(merged.loginTimeout, plug.loginTimeout);
      expect(merged.queryTimeout, plug.queryTimeout);
      expect(merged.maxResultBufferBytes, plug.maxResultBufferBytes);
      expect(merged.initialResultBufferBytes, plug.initialResultBufferBytes);
      expect(merged.streamChunkSizeBytes, 1024 * 1024);
      expect(merged.blockFetchBatchSize, 512);
      expect(merged.sqlPointerCacheMaxSize, 128);
      expect(merged.slowQueryThreshold, recommended.slowQueryThreshold);
      expect(merged.autoReconnectOnConnectionLost, false);
      expect(merged.maxReconnectAttempts, 2);
      expect(merged.reconnectBackoff, const Duration(milliseconds: 250));
      expect(merged.lazyStrings, isTrue);
    });
  });

  group('OdbcRecommendedOptionsMerger.mergePoolOptions', () {
    test('propagates sessionResetOnCheckout from overrides or recommended', () {
      const recommended = odbc.PoolOptions(
        idleTimeout: Duration(minutes: 1),
        maxLifetime: Duration(hours: 2),
        connectionTimeout: Duration(seconds: 10),
        sessionResetOnCheckout: true,
      );
      const plugOverrides = odbc.PoolOptions(
        idleTimeout: Duration(minutes: 5),
        sessionResetOnCheckout: false,
      );

      final merged = OdbcRecommendedOptionsMerger.mergePoolOptions(
        recommended: recommended,
        plugOverrides: plugOverrides,
      );

      expect(merged.idleTimeout, const Duration(minutes: 5));
      expect(merged.maxLifetime, recommended.maxLifetime);
      expect(merged.connectionTimeout, recommended.connectionTimeout);
      expect(merged.sessionResetOnCheckout, isFalse);
    });
  });
}
