import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';

/// Routing policy for pool-based `bulkInsertParallel` on large SQL Server inserts.
final class BulkInsertParallelPolicy {
  BulkInsertParallelPolicy._();

  /// Whether [databaseType] may use the native parallel bulk-insert path.
  static bool supportsParallelBulkInsert(DatabaseType databaseType) {
    return databaseType == DatabaseType.sqlServer;
  }

  /// Whether [requestRowCount] should route to `bulkInsertParallel` instead of
  /// a single-connection `bulkInsert`.
  static bool shouldUseParallel({
    required DatabaseType databaseType,
    required int requestRowCount,
    required int poolSize,
    bool parallelPoolAvailable = true,
  }) {
    if (!parallelPoolAvailable) {
      return false;
    }
    if (!ConnectionConstants.bulkInsertParallelEnabled) {
      return false;
    }
    if (!supportsParallelBulkInsert(databaseType)) {
      return false;
    }
    if (requestRowCount < ConnectionConstants.bulkInsertParallelRowThreshold) {
      return false;
    }
    return ConnectionConstants.bulkInsertParallelismForPoolSize(poolSize) > 1;
  }

  static int parallelismForPoolSize(int poolSize) {
    return ConnectionConstants.bulkInsertParallelismForPoolSize(poolSize);
  }
}
