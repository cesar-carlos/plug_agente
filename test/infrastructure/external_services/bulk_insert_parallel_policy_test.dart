import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/bulk_insert_parallel_policy.dart';

void main() {
  group('BulkInsertParallelPolicy', () {
    test('supportsParallelBulkInsert is SQL Server only', () {
      expect(BulkInsertParallelPolicy.supportsParallelBulkInsert(DatabaseType.sqlServer), isTrue);
      expect(BulkInsertParallelPolicy.supportsParallelBulkInsert(DatabaseType.postgresql), isFalse);
      expect(BulkInsertParallelPolicy.supportsParallelBulkInsert(DatabaseType.sybaseAnywhere), isFalse);
    });

    test('shouldUseParallel requires threshold, pool size, and native pool', () {
      expect(
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: DatabaseType.sqlServer,
          requestRowCount: 50000,
          poolSize: 8,
        ),
        isTrue,
      );
      expect(
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: DatabaseType.sqlServer,
          requestRowCount: 1000,
          poolSize: 8,
        ),
        isFalse,
      );
      expect(
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: DatabaseType.sybaseAnywhere,
          requestRowCount: 100000,
          poolSize: 8,
        ),
        isFalse,
      );
      expect(
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: DatabaseType.sqlServer,
          requestRowCount: 100000,
          poolSize: 2,
        ),
        isFalse,
      );
      expect(
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: DatabaseType.sqlServer,
          requestRowCount: 100000,
          poolSize: 8,
          parallelPoolAvailable: false,
        ),
        isFalse,
      );
    });

    test('shouldUseParallel respects ODBC_BULK_INSERT_PARALLEL_ENABLED=false', () {
      dotenv.loadFromString(envString: 'ODBC_BULK_INSERT_PARALLEL_ENABLED=false');
      expect(
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: DatabaseType.sqlServer,
          requestRowCount: 100000,
          poolSize: 8,
        ),
        isFalse,
      );
      dotenv.clean();
    });
  });
}
