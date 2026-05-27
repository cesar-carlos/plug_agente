# ODBC Pool, Transactions and Runtime Tuning

This document is the source of truth for how `plug_agente` uses the
[`odbc_fast`](https://pub.dev/packages/odbc_fast) package at runtime. It
covers pool sizing and lifecycle, transaction control, async backpressure,
lock-safety, and observability hooks. Defaults, decisions and trade-offs
are documented here so the runtime behavior of the agent stays consistent
across releases.

Cross-references:

- `lib/core/di/service_locator.dart` — boot/reload/shutdown wiring.
- `lib/core/constants/connection_constants.dart` — numeric defaults.
- `lib/infrastructure/pool/odbc_native_connection_pool.dart` — native
  pool wrapper.
- `lib/infrastructure/external_services/odbc_database_gateway.dart` —
  transactional batch + DBMS detection.
- `lib/infrastructure/metrics/odbc_event_bridge.dart` — runtime event
  bus listener.
- `.cursor/rules/project_specifics.mdc` — repository-wide ODBC
  conventions this document complements.

## Runtime mode

The agent always boots the async backend.

```dart
_odbcLocator.initialize(
  useAsync: true,
  asyncWorkerCount: odbcRuntimeTuning.asyncWorkerCount,
  asyncMaxPendingRequests: odbcRuntimeTuning.asyncMaxPendingRequests,
  asyncBackpressureMode: odbc.AsyncBackpressureMode.failFast,
);
```

- `useAsync: true` — non-blocking calls through the worker isolate. The
  agent is a long-lived desktop process and the UI/Hub paths must not
  block on ODBC drivers.
- `asyncWorkerCount` — derived from `OdbcRuntimeTuning.forPoolSize` as
  `min(poolSize, processorCount)` with `ODBC_ASYNC_WORKER_COUNT` as an
  override capped by the same ceiling. The package serializes operations
  on a single connection by the native mutex, so workers only help when
  there are multiple connections or pool checkouts.
- `asyncMaxPendingRequests` — `poolSize * 4` (or aligned to the SQL
  queue worker count, whichever is larger) so the async pool never
  bottlenecks behind the application-level queue.
- `asyncBackpressureMode: failFast` — **intentional**. The application
  already owns admission control through `SqlExecutionQueue`
  (fairness, timeouts, observability). The ODBC async pool rejects
  overflow immediately so the queue stays the single source of truth
  for backpressure decisions. `waitForSlot` is not used.

The `OdbcRuntimeTuning` class is recomputed on every reload
(`reloadOdbcRuntimeDependencies`) so changes to `IOdbcConnectionSettings`
take effect without restarting the process.

## Native pool

The agent uses the `odbc_fast` native pool (`OdbcNativeConnectionPool`)
with typed [`PoolOptions`](https://pub.dev/documentation/odbc_fast/latest/odbc_fast/PoolOptions-class.html).

```dart
PoolOptions get _poolOptions => const PoolOptions(
  idleTimeout: ConnectionConstants.defaultNativePoolIdleTimeout,        // 5 min
  maxLifetime: ConnectionConstants.defaultNativePoolMaxLifetime,        // 1 hour
  connectionTimeout: ConnectionConstants.defaultNativePoolConnectionTimeout, // 30 s
);
```

- **`idleTimeout = 5 min`** — idle connections are evicted before
  network middleboxes drop them silently.
- **`maxLifetime = 1 hour`** — caps how long a single ODBC connection
  may stay in the pool. Recycles connections that may have accumulated
  prepared statement leaks or driver state we cannot inspect from
  outside.
- **`connectionTimeout = 30 s`** — also used as `defaultPoolAcquireTimeout`.

Pool size is `ConnectionConstants.poolSize` (default `4`, env
`ODBC_POOL_SIZE`). The number of pools created at once is capped at
`ConnectionConstants.maxConnectionPools` to prevent runaway allocations
when many connection strings rotate through the agent.

### Checkout validation

`PoolTestOnCheckout` is **on by default** (`settings.nativePoolTestOnCheckout
= true`). Each checkout pays a `SELECT 1` round-trip in exchange for never
handing out a half-dead connection. The default favors correctness over
raw throughput because:

- the agent already serializes SQL behind `SqlExecutionQueue`, so the
  micro-latency rarely shows up in client-perceived response time;
- a stale connection produces failures that bubble all the way to the
  Hub and ultimately to user-facing error messages.

The default can be overridden either per connection string
(`...;PoolTestOnCheckout=false;`) or globally via the
`ODBC_POOL_TEST_ON_CHECKOUT` environment variable, following the package's
contract. Override only after measuring that checkout validation is a
real bottleneck in production.

### Recycle, warmup and orphan handling

- `OdbcNativeConnectionPool` keeps a `Map<String connectionString, int
  poolId>` plus a per-string in-flight creation future to coalesce
  concurrent first-touch requests.
- If a `recycle()` lands while creation is still in flight, the
  freshly-created pool is closed immediately to avoid a leak and the
  caller receives a retryable failure.
- `IConnectionPoolWarmUp.warmUp(connectionString, warmUpCount)` is
  invoked from `AppInitializer._warmUpConnectionPool()` so the first
  Hub-driven query does not pay the full handshake cost.

### Discard and release

The agent treats every checkout as potentially poisoned by the previous
caller:

- `release(connectionId)` → routes to `poolReleaseConnection` (the
  package rolls back leftover local work before returning the slot).
- `discard(connectionId)` → also calls `poolReleaseConnection`. Direct
  `disconnect()` for pool-owned connections returns
  `ValidationError` since `odbc_fast 3.9.0` — pool connections must
  always go back through the pool API.

## Transaction control

Only one call site exists for `_service.beginTransaction` in the entire
codebase: `OdbcDatabaseGateway._beginBatchTransactionIfNeeded`. Every
transactional batch flows through it.

```dart
await _service.beginTransaction(
  connectionId,
  savepointDialect: SavepointDialect.auto,
  accessMode: accessMode,            // inferred per batch (see below)
  lockTimeout: lockTimeout,          // from SqlExecutionOptions
);
```

### Isolation, savepoints, lock timeout

- **`SavepointDialect.auto`** — the engine resolves `SAVEPOINT` vs
  `SAVE TRANSACTION` via `SQLGetInfo`, so cross-engine batches do not
  require a dialect hint from the caller.
- **`lockTimeout`** — derived from `SqlExecutionOptions.timeoutMs` so
  the cap on lock waits scales with the caller's budget. Sub-second
  values are rounded up to 1 s by the package on engines that only
  expose seconds (MySQL, MariaDB, DB2).
- **`accessMode`** — see "Read-only inference" below.

### Read-only inference (lock-safety)

`OdbcDatabaseGateway._inferBatchAccessMode(List<SqlCommand>)` walks
every command in the batch. When **all** commands pass
`SqlValidator.validateSelectQuery` (i.e. start with `SELECT` / `WITH`
and contain no top-level dangerous patterns), the batch is started with
`TransactionAccessMode.readOnly`. Otherwise it stays
`TransactionAccessMode.readWrite`.

The engine-specific effect of `readOnly`:

| Engine | Behavior |
|---|---|
| PostgreSQL | `SET TRANSACTION READ ONLY` → planner can skip locking, pick snapshot reads |
| MySQL / MariaDB | hint for snapshot read |
| Oracle | `SET TRANSACTION READ ONLY` → consistent reads without row locks |
| DB2 | native hint |
| SQL Server / SQLite / Snowflake | silent no-op (no regression vs `readWrite`) |

The counter `transactional_batch_readonly_inference` in the diagnostics
snapshot makes it possible to verify the inference is firing in
production. If the counter stays at zero while the agent is busy, no
batch in that workload is read-only and the optimization has no impact —
that is still useful information.

### Rollback discipline

`_BatchTransactionGuard` ensures every transaction is closed exactly once:

| Trigger | Cleanup |
|---|---|
| Command failure mid-batch | rollback before returning failure |
| Validation failure | rollback + structured failure context |
| Commit failure | rollback (engine-side) + best-effort cleanup |
| Unexpected exception | rollback inside `catch` |
| Deadline already vencido at rollback time | `_rollbackTimeoutFromDeadline` applies a floor so cleanup is not cut mid-flight |
| Native-compatible pool fallback to direct | `recycleAfterRelease` triggers `poolReleaseConnection`, which rolls back leftover work automatically |

The guard is idempotent (`_closed = true` after first call), so repeated
rollback attempts across nested error paths cannot double-execute.

### Deadline near-stall warning

`_maybeRecordTransactionalBatchDeadlineNearStall` runs immediately before
commit. When the batch has already consumed at least 80% of its active
deadline, two things happen:

- the counter `transactional_batch_deadline_near_stall` increments;
- a `developer.log` at level `900` reports `consumed_ratio`,
  `remaining_ms`, `effective_timeout_ms`, `command_count` and a
  suggestion to either raise `timeoutMs` or split the batch.

The signal exists because a commit that races the timeout pushes the
rollback path into the same shrinking budget, and the agent loses the
race to clean up engine-side locks if the deadline runs out mid-rollback.

## DBMS detection

`OdbcDatabaseGateway._mapDriverNameToDatabaseType(String driverName)`
maps the persisted `Config.driverName` to the local `DatabaseType` enum
(`sqlServer`, `postgresql`, `sybaseAnywhere`) used by SQL builders.

1. Exact match on the three legacy strings `'SQL Server'`,
   `'PostgreSQL'`, `'SQL Anywhere'` returns immediately.
2. On miss, the call falls back to the richer
   `odbc.DatabaseType.fromDriverName(driverName)` from the package,
   which recognises `Microsoft SQL Server`, `PostgreSQL Unicode`,
   `Adaptive Server Anywhere`, `mariadb`, `oracle`, `db2`, etc.
3. If the heuristic still returns one of the three supported dialects,
   it is used directly.
4. Otherwise, the call **emits a structured `developer.log` warning at
   level 1000** with `driver_name`, `detected_engine`, and the list of
   supported dialects, then returns `DatabaseType.sqlServer` for
   compatibility with the existing SQL builders.

The fallback is deliberate: the agent currently models only three
dialects in `OdbcPaginatedSqlBuilder` and friends, but silent fallback to
SQL Server SQL on an Oracle connection would produce broken statements.
Loud fallback keeps the misconfiguration visible to operators.

`@visibleForTesting mapDriverNameToDatabaseTypeForTesting` exposes the
method for unit tests in
`test/infrastructure/external_services/odbc_database_gateway_test.dart`.

## Connection options per call path

Every call path that opens a connection uses
`OdbcConnectionOptionsBuilder` to build a `ConnectionAcquireOptions` and
then maps it to `odbc.ConnectionOptions` via
`ConnectionAcquireOptionsMapper`:

| Path | Builder method | `autoReconnect` | `queryTimeout` |
|---|---|---|---|
| Standard pooled query | `forQueryExecution` / `forQueryExecutionWithTimeout` | `true` | `defaultQueryTimeout` = 60 s, or caller-provided |
| Transactional batch | `forTransactionalBatch` | `false` (intentional) | `defaultTransactionalBatchTimeout` = 60 s |
| Streaming | `OdbcStreamingGateway._buildStreamingConnectionOptions` | `true` | `defaultStreamingQueryTimeout` = 5 min |

`autoReconnectOnConnectionLost: false` for transactional batches is the
correct choice: if the connection drops mid-transaction, a silent
auto-reconnect would leave the caller with a stale `transactionId`
referring to a transaction that no longer exists on the server.

`maxResultBufferBytes` is clamped between 8 MB and 128 MB by
`OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb` so neither
under-configuration (0 MB) nor pathological values from the UI corrupt
ODBC fetch behavior.

### Slow query detection

The agent does **not** set `ConnectionOptions.slowQueryThreshold`
explicitly. The package default
(`queryTimeout * 0.8`, exposed through
`ConnectionOptions.effectiveSlowQueryThreshold`) is used everywhere.
For standard queries this means a `SlowQueryDetected` event at ~48 s;
for streaming the threshold lands at ~4 min; for transactional batches
at ~48 s. All three are reasonable budgets given the calling contexts.

## Event bus

`OdbcEventBridge` subscribes to `IAdminService.events` and serves as the
agent's single entry point for runtime observability emitted by
`odbc_fast` itself.

The bridge does three things on each event:

1. **Structured log** through `developer.log` with `name:
   'odbc_event_bridge'`, including relevant payload (`connection_id`,
   `attempt`/`max_attempts`, `pool_id`/`old_size`/`new_size`,
   `duration_ms`, truncated SQL preview for slow queries).
2. **Counter** on `MetricsCollector`. Exposed in the diagnostics
   snapshot under the keys:
   - `odbc_event_connection_lost`
   - `odbc_event_auto_reconnect_attempted`
   - `odbc_event_worker_recovered`
   - `odbc_event_pool_resize`
   - `odbc_event_slow_query_detected`
3. **Ring buffer** of the last `kOdbcEventBridgeMaxRecentEvents` (32)
   events, surfaced as `recent_odbc_events` in
   `OdbcNativeMetricsService.collectSnapshot()`. Dashboards can render
   the most recent runtime events without scraping logs.

The bridge is primed eagerly in `setupDependencies` (after
`OdbcService.initialize()`) so it starts capturing events from boot,
and again in `reloadOdbcRuntimeDependencies` after the locator is
reinitialized. `dispose()` cancels the subscription as part of
`shutdownApp`.

## Diagnostics snapshot

`OdbcNativeMetricsService.collectSnapshot()` is the single entry point
for the diagnostics dashboard. It aggregates:

- `engine` — `service.getMetrics()` (queryCount, latency, uptime).
- `prepared_statements` — `service.getPreparedStatementsMetrics()`.
- `connection` — `validateConnectionString` result.
- `driver_capabilities` — `getDriverCapabilities` result.
- `app_pool` — health diagnostics from `IConnectionPool` +
  active count.
- `native_pool` — `poolGetStateDetailed` for the active connection
  string.
- `async_worker_pool` — `service.getWorkerPoolStats()` (returns
  `null` in sync mode → `{'available': false}` in the snapshot).
- `runtime_tuning` — current `OdbcRuntimeTuning` values.
- `sql_queue` — counters from the application-level queue.
- `recent_odbc_events` — bridge ring buffer.

Async worker pool saturation (pending requests > 80% of cap) is logged
once per saturation episode to avoid log spam.

## Streaming

`OdbcStreamingGateway` uses `_service.streamQuery(connectionId, sql)`.
The streaming path is single-purpose:

- non-parameterized SQL only (parameterized queries go through
  `executeQueryNamed` and are materialized);
- the streaming chunk size is set by the caller; the gateway clamps
  `initialResultBufferBytes` and `maxResultBufferBytes` to safe values;
- streaming connections explicitly opt into `autoReconnectOnConnectionLost`
  with bounded retry attempts because streaming queries are
  idempotent reads.

The package's `streamQueryBatched` is the low-level
`NativeOdbcConnection`/`PreparedStatement` form and is intentionally not
used through the high-level service.

## Bulk insert

`OdbcDatabaseGateway` uses sequential `_service.bulkInsert` from a
direct (non-pooled) connection. Parallel bulk via
`bulkInsertParallel(poolId, ...)` is **not** wired today; it would
require exposing `poolId` on `IConnectionPool` and adding a threshold
on row count. Without profiling indicating mega-bulks (10k+ rows) are a
hot path, the simpler sequential form is the safer choice on a critical
write path.

`_bulkInsertRecommendationCommandThreshold = 50` already promotes the
`bulk_insert` shape over `INSERT` loops when the caller submits more
than 50 homogeneous `INSERT` commands in a single batch.

## Counters and metric keys

For Grafana/Prometheus-style dashboards, the snapshot keys relevant to
ODBC are:

- Pool lifecycle:
  - `pool_release_failure`, `pool_recycle`, `pool_recycle_failure`
  - `pool_acquire_timeout_count` (under `sql_queue`)
- Native pool fallbacks:
  - `odbc_native_pool_fallback`, `odbc_native_fallback_total`,
    `odbc_native_circuit_opened_total`, `odbc_invalid_connection_recycle_total`
- Native-compatible acquire:
  - `odbc_native_compatible_acquire_attempt`,
    `odbc_native_compatible_acquire_success`
- Direct connection:
  - `direct_connection_acquire_timeout`, `direct_connection_fallback`
- ODBC runtime events (via `OdbcEventBridge`):
  - `odbc_event_connection_lost`, `odbc_event_auto_reconnect_attempted`,
    `odbc_event_worker_recovered`, `odbc_event_pool_resize`,
    `odbc_event_slow_query_detected`
- Transactional batch:
  - `transactional_batch_readonly_inference` — read-only hint fired
  - `transactional_batch_deadline_near_stall` — batch ≥80% of deadline
    on commit

## Decision log

- **Stay on `failFast` instead of `waitForSlot`.** `SqlExecutionQueue`
  is already the application-level admission controller.
- **Keep `nativePoolTestOnCheckout = true` by default.** Hub-facing
  failures are more expensive than a `SELECT 1` per checkout.
- **Keep `autoReconnectOnConnectionLost = false` on transactional
  batches.** A silent reconnect would corrupt the transaction state.
- **Keep `runInTransaction<T>` of the package out of the agent for
  batch flow.** The batch needs deadline-aware rollback timeouts,
  partial command-result reporting and native-pool fallback that the
  helper does not model.
- **Defer `executeQueryColumnar` / `TypedColumnarResult` adoption.**
  Would require changing the JSON-RPC schema and the dashboard
  contract; no profiling pointing at boxed-row decoding as a hot path.
- **Defer `bulkInsertParallel`.** Critical write path; refactor cost
  exceeds expected gain without profiling on real workloads.
- **Defer cancellation tokens on batches.** No evidence that abandoned
  RPC clients are a frequent cause of stuck locks today.
