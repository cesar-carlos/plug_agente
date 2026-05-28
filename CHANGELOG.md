# Changelog

All notable technical changes to Plug Agente are tracked here. Release process
and version bump instructions remain in `docs/install/release_guide.md`.

## Unreleased

## 1.8.0 - 2026-05-28

### Fixed

- The silent auto-update flow no longer made the agent appear offline or
  reject queries while an update was pending. The previous cycle could
  block the install path mid-flight when UAC would prompt the user,
  leaving the connection in a state where every new query returned an
  access-denied error until the operator updated manually. The flow now
  keeps the connection alive end-to-end; the install only happens after
  an explicit user gesture.

### Added

- New `IUacDetector` abstraction (`lib/core/runtime/i_uac_detector.dart`)
  with a Windows implementation (`WindowsUacDetector`) and a `NoopUacDetector`
  used by tests and non-Windows platforms. The Windows backend resolves
  the process token elevation type via `OpenProcessToken` +
  `GetTokenInformation(TokenElevationType)` and reads the `EnableLUA`
  policy from the **64-bit hive** (`KEY_QUERY_VALUE | KEY_WOW64_64KEY`)
  so 32-bit builds are not redirected to `Wow6432Node`. The detector
  exposes a rich `UacDetectionState` snapshot (`elevationType`,
  `uacEnabled`, `requiresConsent`, `detectionError`) for diagnostics
  and a boolean `requiresUserConsentForElevation()` for the gate. The
  result is cached for the process lifetime by default with an optional
  `cacheTtl` for long-lived sessions.
- New `SilentUpdateOutcome.requiresUserConsent` and
  `UpdateCheckCompletionSource.automaticAwaitingUserConsent` discriminate
  the "probe found a newer version but UAC blocks unattended install"
  state from the existing flow. The coordinator persists the diagnostic
  so the UI can render the banner on next boot even before the periodic
  probe runs.
- New `IAutoUpdateOrchestrator.hasUpdateAwaitingUserConsent` getter and
  `applyAvailableUpdate({noticeTitle, noticeBody})` method bridge the
  in-app banner to the user-initiated flow. `applyAvailableUpdate`
  pauses the periodic timer, calls
  `SilentUpdateCoordinator.checkSilently(userInitiated: true)` to bypass
  the UAC gate, applies the staged installer, and restores the timer in
  `finally` so a flake never leaves the coordinator permanently stopped.
- New auto-update metrics in `IAutoUpdateMetricsCollector`:
  `recordAutoUpdateAwaitingUserConsent()`,
  `recordAutoUpdateUserInitiatedApplySuccess()` and
  `recordAutoUpdateUserInitiatedApplyFailure()`. The `MetricsCollector`
  snapshot exposes matching `autoUpdateAwaitingUserConsentCount`,
  `autoUpdateUserInitiatedApplySuccessCount` and
  `autoUpdateUserInitiatedApplyFailureCount` counters so operations can
  dimension the gate hit rate and operator follow-through.
- `AutoUpdateReadyBanner` now handles both the "downloaded and ready"
  and "awaiting UAC consent" states through a shared surface. The UAC
  variant renders with the `shield_solid` icon, the `warning` feedback
  tone, localized title/body explaining the elevation requirement, and
  a "Download and install" primary action. A phase indicator next to
  the spinner labels the in-flight stage (`downloading`, `staging`,
  `launching`).
- "Remind me later" on the banner now persists to `IAppSettingsStore`
  via the new `AppSettingsKeys.autoUpdateBannerDismiss` key with a 6-hour
  TTL. The banner hydrates the dismiss state on `initState`, hides the
  surface while the TTL is active, and re-appears when the TTL expires
  or the pending version changes.

### Changed

- `SilentUpdateCoordinator.checkSilently` accepts a new `userInitiated`
  flag (default `false`). The automatic flow stops after the probe when
  `userInitiated == false` and `IUacDetector.requiresUserConsentForElevation()`
  returns `true`; passing `true` from the banner bypasses the gate so
  the operator's explicit click consents to the upcoming UAC prompt.
- `SilentUpdateCoordinator.hydratePersistedDiagnostics()` now reconciles
  stale `automaticAwaitingUserConsent` snapshots on startup: when the
  persisted `pendingVersion` is already at or below
  `AppConstants.appVersion`, the diagnostic is rewritten to
  `automaticUpdateNotAvailable` so the banner does not show after the
  operator updated out of band.
- `AutoUpdateOrchestrator.applyAvailableUpdate` translates non-
  `installerReady` outcomes into typed `Failure`s with the originating
  `outcome` preserved in `context`. The banner reads the context and
  renders a localized, actionable message via the new
  `autoUpdateApplyOutcomeCooldown/SilentDisabled/Cancelled/QuietHours/`
  `NoNewVersion/AlreadyInProgress/PendingInProgress/Unknown` strings
  (English + Portuguese).

### Migration notes

- No setting or schema migration is required. The `auto_update_banner_dismiss`
  preference is created on demand.
- The `ISilentUpdateCoordinator.checkSilently` contract grew a named
  `userInitiated` parameter with a `false` default; existing call sites
  continue to compile and behave as before.

## 1.7.2 - 2026-05-28

### Fixed

- `ConnectionProvider` now wraps recovery handlers (`_handleReconnectionNeeded`
  and `_handleTokenExpired`) in `finally` so an unexpected `Error` escape or an
  early `return` triggered by user disconnect cannot leave `_isReconnecting=true`
  and permanently block hub recovery.
- `BackpressureStreamEmitter` catches flush failures, marks the emitter as
  faulted, short-circuits subsequent `emitChunk`/`releaseChunks` and unregisters
  itself from the registry. Previously a single `_emit` failure poisoned the
  in-flight chain via `.then(...)` propagation, silently dropping every future
  chunk while the hub kept waiting. New `isFaulted` getter exposes the state.
- `MetricsCollector` and `ProtocolMetricsCollector` now use `ListQueue` for the
  ring buffer of recent metrics, so capping is O(1) instead of O(n) via
  `removeRange(0, ...)`. Protocol metrics fire on every transport send/receive;
  the previous pattern caused millions of element shifts per second under load.

### Changed

- `RetryManager` applies multiplicative jitter (±20% default) on each retry
  delay with an injectable `Random` for deterministic tests, preventing
  synchronized retry storms after circuit-breaker or network blips.
- `AutoUpdateOrchestrator.checkInBackground` bounds the trigger via
  `backgroundTriggerTimeout` (default 30s) so an unresponsive updater process
  cannot block the retry loop indefinitely. The retry backoff also gains ±20%
  jitter to avoid synchronized retries across fleets of agents.
- `SqlExecutionQueue.disposeGracefully(timeout)` now drains in-flight workers
  with a timeout before the pool is closed; the service locator awaits it
  between transport disconnect and `pool.closeAll` so ODBC leases are
  released cleanly during shutdown.
- `OdbcStreamingGateway` rejects duplicate `executionId` before acquiring the
  lease and connecting, and skips the no-op
  `DirectOdbcConnectionLimiter.reconfigureMaxConcurrent` call when the pool
  size has not changed.

### Performance

- `AgentActionRepository.saveExecution` no longer re-reads captured output
  chunks immediately after persisting them. The original text is preserved in
  memory; chunks are loaded only on status-only updates that pass no text.
- `DriftIdempotencyStore` throttles `updated_at` LRU writes (default once per
  minute per hot key) and skips the per-`set` `_deleteExpired` DELETE — the
  periodic purge and LRU eviction already cover expired entries.
- `AgentActionRemoteAuditDriftStore.deleteWhereOccurredBefore` replaces the
  previous SELECT-then-DELETE pair with a single
  `DELETE … WHERE id IN (subquery)` that uses the existing
  `idx_agent_action_remote_audit_occurred` index.

### Added

- `ConnectionCircuitBreakerCache` provides a shared LRU-bounded cache
  (default 16 entries) for the per-connection-string breakers used by
  `OdbcDatabaseGateway` and `OdbcStreamingGateway`, closing a slow memory leak
  on long sessions with connection-string churn.
- `ConnectionCircuitBreaker` throttles its OPEN-state fast-fail log (first
  rejection + every Nth) and exposes `openStateRejectionCount` for diagnostics.
- `SqlExecutionQueue` throttles the queue-full rejection log the same way and
  exposes `consecutiveFullRejections` for diagnostics.

## 1.7.1 - 2026-05-27

### Fixed

- Editing a client token from the settings UI no longer regenerates the
  opaque secret on every save. The token is now rotated only when the
  authorization policy actually changes (scope flags, global permissions
  or resource rules). Pure metadata edits (name, agentId, payload,
  clientId) preserve the existing token value, hash and secure-storage
  entry. Saving a dialog without changes is detected as a no-op and
  skips the database write entirely.

### Changed

- Reordering resource rules in the edit dialog is treated as the same
  policy and no longer triggers rotation, thanks to the new
  `ClientTokenAuthorizationPolicy` value object with order-insensitive
  rule equality.
- `ClientTokenUpdateResult` now exposes a `ClientTokenUpdateOutcome`
  (`unchanged | metadataOnly | rotated`); `tokenValue` is nullable and
  populated only on rotation.
- `UpdateClientToken` use case now invalidates authorization caches and
  records a `rotate` audit event only on actual rotation; metadata-only
  edits record a new `metadataUpdate` audit event and skip cache
  invalidation; no-op edits record nothing.

### Added

- `TokenAuditEventType.metadataUpdate` to distinguish metadata edits
  from secret rotations in the audit trail.
- Edit dialog shows an inline hint tailored to the current state
  ("Saving will rotate the token", "No rule changes - token kept",
  or "No changes to save") and disables the Save button when the form
  has no diff against the snapshot.
- After saving an edit, an InfoBar surfaces the outcome on the section
  page; on rotation the new token value is shown with a one-click copy
  action so operators can redistribute it before navigating away.

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
