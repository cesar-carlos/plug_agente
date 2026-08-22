import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';

void main() {
  group('ConnectionAcquireOptionsMapper.toOdbcConnectionOptionsForConnectionString', () {
    const options = ConnectionAcquireOptions(
      queryTimeout: Duration(seconds: 30),
      maxResultBufferBytes: 1024 * 1024,
    );

    test('enables lazyStrings for SQL Server connection strings', () {
      final mapped = options.toOdbcConnectionOptionsForConnectionString(
        'Driver={ODBC Driver 18 for SQL Server};Server=localhost;',
      );
      expect(mapped.lazyStrings, isTrue);
      expect(mapped.queryTimeout, options.queryTimeout);
      expect(mapped.blockFetchBatchSize, ConnectionConstants.defaultBlockFetchBatchSize);
      expect(mapped.streamChunkSizeBytes, ConnectionConstants.defaultStreamingChunkSizeKb * 1024);
      expect(mapped.blockFetchBatchSize, ConnectionConstants.defaultBlockFetchBatchSize);
      expect(mapped.streamChunkSizeBytes, ConnectionConstants.defaultStreamingChunkSizeKb * 1024);
    });

    test('enables lazyStrings for PostgreSQL connection strings', () {
      final mapped = options.toOdbcConnectionOptionsForConnectionString(
        'Driver={PostgreSQL Unicode};Server=localhost;',
      );
      expect(mapped.lazyStrings, isTrue);
    });

    test('enables lazyStrings for SQL Anywhere connection strings', () {
      final mapped = options.toOdbcConnectionOptionsForConnectionString(
        'Driver={SQL Anywhere 17};ENG=demo;',
      );
      expect(mapped.lazyStrings, isTrue);
    });

    test('leaves lazyStrings false for unrecognized drivers', () {
      final mapped = options.toOdbcConnectionOptionsForConnectionString(
        'Driver={SomeOtherDriver};Server=localhost;',
      );
      expect(mapped.lazyStrings, isFalse);
    });
  });
}
