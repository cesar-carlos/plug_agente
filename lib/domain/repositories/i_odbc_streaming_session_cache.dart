import 'package:result_dart/result_dart.dart';

/// Invalidates short-TTL ODBC streaming connection reuse entries.
abstract interface class IOdbcStreamingSessionCache {
  void invalidate({String? connectionString});

  /// Clears cached entries and disconnects each cached ODBC connection id.
  Future<Result<void>> drainCachedSessions();
}
