# Changelog

All notable technical changes to Plug Agente are tracked here. Release process
and version bump instructions remain in `docs/install/release_guide.md`.

## Unreleased

## 1.7.0 - 2026-05-27

### Changed

- Updated `odbc_fast` to `^3.10.1` (previous wave bumped to `3.8.1`, this
  release lands the full minor 3.9 → 3.10 plus the 3.10.1 patch).
- Migrated `OdbcNativeMetricsService` from the deprecated
  `IOdbcRepository.getAsyncWorkerPoolStats()` to the new infallible
  `IAdminService.getWorkerPoolStats()` (returns `null` in sync mode instead
  of `Failure(UnsupportedFeatureError)`).
- Inferred `TransactionAccessMode.readOnly` for transactional batches whose
  every command passes `SqlValidator.validateSelectQuery`, so
  PostgreSQL/MySQL/MariaDB/DB2/Oracle skip locking on read-only units of
  work. SQL Server / SQLite / Snowflake silently no-op so the change is a
  pure improvement on engines that honour the hint.
- Hardened `_mapDriverNameToDatabaseType`: it now falls back to the richer
  `odbc_fast.DatabaseType.fromDriverName` heuristic (catches
  `Microsoft SQL Server`, `PostgreSQL Unicode`, `Adaptive Server Anywhere`,
  etc.) and emits a structured warning when the detected engine is outside
  the three locally supported dialects, replacing the previous silent
  fallback to SQL Server.
- Enabled adaptive ODBC pooling by default for eligible SQL Server/PostgreSQL
  drivers while keeping SQL Anywhere on the lease/direct path.
- Added a transactional DML batch fast path that can use the
  native-compatible adaptive pool and falls back to the direct path on
  structural failures.
- Kept explicit async worker tuning (`min(poolSize, CPU cores)`,
  `poolSize * 4`, `failFast`) because `SqlExecutionQueue` remains the
  app-level backpressure boundary; the `failFast` decision is now
  documented inline at the `ServiceLocator.initialize(...)` call sites.

### Added

- New `OdbcEventBridge` subscribed to `IAdminService.events`. Fans every
  variant of the sealed `OdbcEvent` hierarchy (`ConnectionLost`,
  `AutoReconnectAttempted`, `WorkerRecovered`, `PoolResize`,
  `SlowQueryDetected`) out to structured logs, `MetricsCollector` counters
  and a bounded ring buffer of the last 32 events. Lifecycle wired through
  `ServiceLocator` (boot priming, `reloadOdbcRuntimeDependencies` and
  `shutdownApp`).
- New counters in `MetricsCollector`:
  - `odbc_event_connection_lost`, `odbc_event_auto_reconnect_attempted`,
    `odbc_event_worker_recovered`, `odbc_event_pool_resize`,
    `odbc_event_slow_query_detected` (forwarded by the bridge);
  - `transactional_batch_readonly_inference` (the new read-only hint
    actually fired for a transactional batch);
  - `transactional_batch_deadline_near_stall` (the batch reached commit
    having consumed at least 80% of its active deadline).
- New `recent_odbc_events` block in
  `OdbcNativeMetricsService.collectSnapshot`, serialising each captured
  event per `OdbcEvent` variant for dashboards.
- Pre-commit warning when a transactional batch consumes at least 80% of
  the active deadline, with structured payload pointing at the recommended
  remediation (raise `timeoutMs` or split the batch) so lock-stuck risk is
  surfaced before it materialises.
- Added stable metrics for transactional native pool usage and fallback:
  `transactional_batch_native_pool_path` and
  `transactional_batch_native_pool_fallback`.
- Added `batch_bulk_insert_recommended` / `batch.bulk_insert_recommended_total`
  diagnostics for large homogeneous `INSERT` batches that should be migrated
  to `sql.bulkInsert`.
- Added `tool/odbc_streaming_benchmark.ps1` to compare `streamQuery` and
  `streamQueryBatched` from the `odbc_fast` examples with the app `.env`; it
  now defaults to the representative long query when available.
- Added `tool/odbc_driver_matrix_benchmark.ps1` and wired it into operational
  validation to benchmark configured SQL Anywhere, SQL Server and PostgreSQL
  DSNs separately.
- Added automatic burst health snapshots in ODBC operational validation.
- Added `ODBC_RESULT_ENCODING` as an opt-in result encoding flag for
  parameterized ODBC queries; `rowMajor` remains the default.
- Added a no-DSN `odbc_fast` runtime smoke to validate async worker startup
  and columnar/compressed native exports before operational ODBC runs.
- Added 16 new unit tests covering the read-only inference (both branches),
  the enriched driver-name mapper (exact match + heuristic + structured
  warning fallback + unknown driver), the bridge counter wiring, the
  bounded ring buffer, the `recent_odbc_events` snapshot block and the new
  `getWorkerPoolStats` contract.
- Cached derived lists in `AgentActionsProvider` to reduce repeated
  filtering work during UI rebuilds.

### Documentation

- New `docs/runtime/odbc_pool_and_transactions.md` consolidating the
  agent's pool, transaction, async/runtime, event bus and diagnostics
  conventions, including a decision log for items deferred (`failFast` vs
  `waitForSlot`, `runInTransaction` adoption, `executeQueryColumnar`,
  `bulkInsertParallel`, cancellation tokens on batches).
- Documented the `odbc_fast 3.10.x` operational validation path and
  streaming benchmark workflow.

### Notes

- `feature_enable_odbc_experimental_driver_adaptive_pooling=false` remains
  a persisted opt-out.
- `service.streamQuery` already uses the package batched-first path in
  `odbc_fast 3.10.x`; no low-level streaming bypass was added.
- The manual transaction path was kept because it owns app-specific
  failure mapping, metrics, rollback, native-pool fallback semantics and
  deadline-aware rollback timeouts that `runInTransaction<T>` in the
  package does not model.
- `bulkInsertParallel(poolId, ...)`, `executeQueryColumnar` and
  cancellation tokens on batches were evaluated and deferred — see the
  decision log in `docs/runtime/odbc_pool_and_transactions.md` for the
  rationale.

### Validation

- `flutter analyze`: clean (no issues).
- `flutter test`: 2931 passed, 11 skipped (live opt-in), 0 failed.
- `flutter test --exclude-tags "live || slow || perf"`: 2916 passed, 0
  failed.
