import 'package:result_dart/result_dart.dart';

/// ODBC connection pool contract used by the database gateway.
///
/// Lifecycle:
/// - Each successful [acquire] yields a connection id that must be passed to
///   [release] when the caller is done (pairing is the caller's responsibility).
/// - [closeAll] tears down every pooled / leased handle; waiters blocked on
///   capacity (lease pool) are completed with an error so they do not hang.
/// - Implementations should map transport errors to [Failure] with stable
///   `operation` context for diagnostics (`pool_acquire`, `pool_release`, etc.).
abstract class IConnectionPool {
  /// Obtains a connection id for [connectionString] (new handle or pooled).
  Future<Result<String>> acquire(String connectionString);

  /// Returns a connection to the pool or disconnects the lease, depending on impl.
  ///
  /// Lease pool: on [Failure] (e.g. disconnect error), the implementation may
  /// keep the lease slot reserved so the connection id is not double-used; callers
  /// may need [recycle] / [closeAll] / process restart. See concrete pool docs.
  Future<Result<void>> release(String connectionId);

  /// Closes every connection / native pool tracked by this instance.
  Future<Result<void>> closeAll();

  /// Drops resources for [connectionString] so the next [acquire] starts fresh.
  ///
  /// Lease pool: disconnects all active leases for that string. Slots are always
  /// released even if a disconnect fails; if any disconnect fails, returns
  /// [Failure] aggregating messages (same spirit as [closeAll]).
  Future<Result<void>> recycle(String connectionString);

  /// Best-effort count of in-use connections (semantics depend on implementation).
  Future<Result<int>> getActiveCount();

  /// Runs a health check on native pools when supported; lease pool is a no-op.
  Future<Result<void>> healthCheckAll();

  /// Pre-opens idle lease connections for [connectionString] (lease pool only).
  ///
  /// Native pool implementations return success without work. When idle reuse
  /// is disabled (TTL zero), returns success immediately.
  Future<Result<void>> warmIdleLeases(String connectionString);
}
