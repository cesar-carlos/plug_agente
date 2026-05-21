# Changelog

All notable technical changes to Plug Agente are tracked here. Release process
and version bump instructions remain in `docs/install/release_guide.md`.

## Unreleased

### Changed

- Updated `odbc_fast` to `^3.8.0`.
- Enabled adaptive ODBC pooling by default for eligible SQL Server/PostgreSQL
  drivers while keeping SQL Anywhere on the lease/direct path.
- Added a transactional DML batch fast path that can use the native-compatible
  adaptive pool and falls back to the direct path on structural failures.
- Kept explicit async worker tuning (`min(poolSize, CPU cores)`,
  `poolSize * 4`, `failFast`) because `SqlExecutionQueue` remains the app-level
  backpressure boundary.

### Added

- Added stable metrics for transactional native pool usage and fallback:
  `transactional_batch_native_pool_path` and
  `transactional_batch_native_pool_fallback`.
- Added `batch_bulk_insert_recommended` / `batch.bulk_insert_recommended_total`
  diagnostics for large homogeneous `INSERT` batches that should be migrated to
  `sql.bulkInsert`.
- Added `tool/odbc_streaming_benchmark.ps1` to compare `streamQuery` and
  `streamQueryBatched` from the `odbc_fast` examples with the app `.env`; it
  now defaults to the representative long query when available.
- Added `tool/odbc_driver_matrix_benchmark.ps1` and wired it into operational
  validation to benchmark configured SQL Anywhere, SQL Server and PostgreSQL
  DSNs separately.
- Added automatic burst health snapshots in ODBC operational validation.
- Documented the `odbc_fast 3.8.0` operational validation path and streaming
  benchmark workflow.
- Cached derived lists in `AgentActionsProvider` to reduce repeated filtering
  work during UI rebuilds.

### Notes

- `feature_enable_odbc_experimental_driver_adaptive_pooling=false` remains a
  persisted opt-out.
- `service.streamQuery` already uses the package batched-first path in
  `odbc_fast 3.8.0`; no low-level streaming bypass was added.
