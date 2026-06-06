import 'package:result_dart/result_dart.dart';

/// Native ODBC pool handle used for pool-scoped bulk insert operations.
abstract interface class IOdbcNativeBulkInsertPool {
  /// Ensures a native `odbc_fast` pool exists for [connectionString] and
  /// returns its pool id.
  Future<Result<int>> ensurePoolId(String connectionString);
}
