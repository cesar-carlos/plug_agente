# Changelog

All notable technical changes to Plug Agente are tracked here. Release process
and version bump instructions remain in `docs/install/release_guide.md`.

## Unreleased

### Added

- Installer handshake marker so an elevated setup can register HKCU auto-start
  for the interactive user on first launch (`autostart-requested`).
- Windows Error Reporting relaunches the agent into the tray (`--autostart`)
  after a crash or hang once it ran for 60s (`RegisterApplicationRestart`,
  Release only; patch and reboot excluded). `setup.iss` sets
  `RestartApplications=no` so Restart Manager never starts a second instance.
- Startup diagnostic (Settings copy) includes stored preference, last
  `--autostart` launch, pending installer request, boot validation outcome,
  and raw `StartupApproved` bytes. A registry read failure is written into
  the report instead of blocking the copy.
- Opt-in live registry test (`RUN_LIVE_STARTUP_REGISTRY_TESTS=true`) uses a
  temporary HKCU value and never touches the installed `Plug Agente` entry.
- ODBC transaction-control benchmark and streaming disconnect tracker for
  timed-out native `disconnect` (handle is discarded, never returned to cache).
- Outbound response capacity gate
  (`reason: outbound_response_capacity_exceeded`); `agent.getHealth` exposes
  occupancy plus agent-action process counters (no PID, path, command, or
  secret). Benchmark suite adds opt-in `odbc_hot_paths` and
  `comparison_identity`.
- Adaptive `auto`-GZIP skip cache (30s TTL) and shared `TransportWorkPool`
  (`TRANSPORT_WORKER_POOL_SIZE`, default 2, clamped 1..4). Large materialized
  `SELECT` results promote to streaming above min(512 KiB, a quarter of
  `max_decoded_payload_bytes`).
- Client-token runtime restrictions (`payload.database`, agent-action
  scopes/allowlist) are validated in Settings and rotate the opaque secret
  when they change authorization.
- Inbound `PayloadFrame` bounds checks run before HMAC (negative sizes, binary
  length vs `compressedSize`, negotiated limits, gzip inflation →
  `invalid_payload` / `compressionFailed`).
- Installer installs Visual C++ Redistributable x64 when missing and registers
  `plugdb://` under HKLM (removed on uninstall).

### Changed

- System Actions empty state lists every editor kind (including PowerShell,
  which still persists as command line or script) and wraps those labels.
  Local run, test, and bundle transfer are mutually exclusive; tabs/dialogs
  rebuild only when their own state changes. Portuguese copy on this page
  uses accents; the remote-audit tab label is "Auditoria remota". The tab
  strip sizes to content, ellipsizes with a tooltip, and scrolls at the
  900x650 minimum window. The action editor dialog fits that height.
- `agent.action.run` / `validateRun` resolve an enabled `remote` trigger
  before rate-limit and enqueue. `cancel` / `getExecution` rate-limit by
  the execution `action_id`. Captured-output RPC/UI windows are UTF-8
  aligned and slice Drift chunks without loading the full stream.
- Handshake `agentActions.supportedTypes` advertises only remote adapters
  (`executable`, `script`, `jar`). Free-form `commandLine` is local-UI only
  (Hub/scheduler/lifecycle rejected); preflight rejects newlines, over-length
  commands, and `${secret:...}` in the command text. Local Windows runs attach
  a Job Object; `agent.action.cancel` targets that process tree.
- Elevated helper build uses `dart build cli` (sqlite3 3.x native hooks)
  instead of `dart compile exe`.
- Windows login with `--autostart` stays in the tray; the unused
  “start minimized” preference was removed from Settings. Disabling auto-start
  deletes machine-scope Run values before HKCU (declined UAC leaves the
  toggle intact). `StartupApproved` uses the low bit (odd = disabled);
  unclassifiable overlays count as a user choice and are not overwritten.
- User-initiated silent install (`Instalar agora`) no longer waits on quiet
  hours or automatic failure cooldown.
- Inno silent updates wait for the app pre-close budget (helper PID wait ≥ 70s)
  and relaunch only via `[Run]` (`/LAUNCHAFTERUPDATE=1`), not
  `/RESTARTAPPLICATIONS`.
- Direct dependencies bumped to latest resolvable majors (`odbc_fast` 4.5.1,
  `drift`/`sqlite3` 3.x, `get_it` 9, `win32` 6, `file_picker` 12,
  `flutter_secure_storage` 11, Syncfusion 34, and related packages).
  `sqlite3_flutter_libs` was removed (EOL; native SQLite comes from `sqlite3`
  3.x Dart hooks).
- Streaming/lease ODBC connections now send `blockFetchBatchSize: 256` when no
  profile overrides it. Transactional bulk uses one connection (sequential
  chunks); parallel/BCP is refused when atomicity is required.
- ODBC session recovery: driver `autoReconnect` is off; only read-only
  statements retry after a lost session. Dead pooled sessions are discarded
  and an idle pool is recycled at most every 5s; after five fast quarantine
  retries the native pool keeps trying every 30s. One circuit breaker cache
  is shared across gateway, streaming, batch, and bulk. Failures go to
  `plug_agente_errors.log` with request id and DSN fingerprint (never SQL,
  parameters, or the connection string). Read-only batch and bulk parallelism
  scale with pool size; `ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD` defaults to
  1000 (was 50000).
- `sql.execute` parses once into `PreparedSql` and reuses the comment-stripped
  form for validation, classification, auth, and streaming policy; the original
  SQL is still sent to ODBC. Default query-stage budget follows the ODBC
  query timeout (60s, total 65s).
- SQL cancel ownership is a credential hash for streaming, materialized,
  batched, and queued work. Mismatch is `-32002` `unauthorized` /
  `cancel_token_mismatch` (was `-32602`). Duplicate active `request_id` is
  `active_sql_request_id_conflict`. Auth logs cover `agent.action.*`; only
  `token_revoked` refreshes hub credentials.
- Disconnect and L0 reconnect invalidate `transportSessionGeneration` before
  re-register (capabilities, pipeline cache, inbound ACKs, prior-generation
  work). `hub:heartbeat_ack` is accepted only for the active `trace_id` and
  epoch. Large HMAC sign/verify runs in an isolate; protocol health adds
  `hmac_sign_isolate_operations` / `hmac_verify_isolate_operations`.
- Streaming disconnect cleanup uses a bounded, deduplicated queue; when
  saturated, new cleanup is refused with a retryable failure. Cached streaming
  sessions keep their direct-limiter reservation.
- Tray preferences apply at runtime before persisting (rollback on save
  failure); Settings gates toggles on `ITrayService.isReady`. A tray init
  failure shows the window for that session and keeps stored preferences.
  Client-token policy cache uses single-flight resolution; revoke/rotate drops
  pending lookups.
- Inno wizard: Brazilian Portuguese first, branded images, `lzma2/ultra64`,
  `Se7e Sistemas` publisher info. Release signing passes `SignTool` to ISCC
  (`SignedUninstaller=yes`); `CloseApplications=force` for a running
  `plug_agente.exe`.
- CI: Flutter workflow split into `analyze`, `test`, `agent-actions-gate`,
  `verify-code-generation`, and `iss-syntax`; `workflow-sanity` validates CI
  configuration; Dependabot for GitHub Actions; appcast signing tests run in
  CI.

### Fixed

- Stale hub connect timeouts and `connect_error` events no longer tear down a
  newer socket; overlapping connect attempts complete instead of hanging.
- Socket.IO manager reconnect no longer double-emits `agent:register` after the
  initial handshake; L0 reconnect can read the current JWT via `setAuthFn`.
- Disconnect during delayed hub recovery no longer treats a later success as
  restored; terminal auth failures stop persistent retry instead of storming.
  A missing auth bridge skips token refresh and keeps the current JWT so
  reconnect can proceed. The negotiating watchdog still kicks recovery;
  leftover kicks are ignored only after protocol-ready.
- Hub protocol-ready during `connecting` is latched until negotiating so the
  watchdog does not kick a false recovery.
- System Actions UI: remote audit listens for refresh; paged stdout/stderr
  no longer reset on parent rebuild or apply a stale slice; shortcuts and
  editor opens are gated while another modal is pending; run/delete confirm
  re-checks the same action; maintenance toggle failures surface to the
  user; refresh is disabled during run/test/transfer.
- Agent-action scheduler: maintenance/feature-off cancels armed timers;
  save/delete resyncs timers; app-start/app-close fire once per process;
  interval/daily slots do not double-fire at the exact boundary; unknown
  IANA timezones fail instead of falling back to local time; failed
  dispatch does not mark `lastRunAt`; overlapping periodic purges are
  skipped.
- Local execution: thrown queue tasks no longer deadlock the slot;
  last-chunk cancel does not treat an already-exited process as
  kill-failed; cancel/timeout persist as those statuses instead of
  generic `failed`; concurrent same-key runs reserve idempotency before
  await; stdin flush/close times out; UTF-8 capture does not split a
  code unit; reconcile continues after a single save error; elevated
  UAC cancel (1223) does not write the ready marker; abort stops status
  polling.
- Bundle import reports `partial_import` with ids already saved; export
  lists triggers once instead of per definition; definition/trigger upserts
  keep `createdAt`; secret `exists` uses `containsKey` without reading the
  value; `cancel` / `getExecution` audit rows include `action_id` and skip
  hydrating captured output during authorization prefetch; remote-audit
  append logs no longer include `idempotencyKey`.
- Windows auto-start: failed Run/StartupApproved writes roll back; the
  installer marker heals HKCU; Task Manager disable is honored without
  self-heal; debug/`flutter run` paths stay out of the Run key. A
  `--autostart` bootstrap failure reveals the hidden window instead of
  holding the single-instance mutex. Auto-start errors (including a locked
  marker) no longer abort boot. Unanswered UAC times out after 2 minutes.
  An explicit Settings toggle clears a pending installer request. Machine
  delete elevates directly (no localized `reg.exe` parsing). Uninstall
  removes HKLM Run (64/32-bit), `StartupApproved`, and Run values of
  signed-in `HKEY_USERS` profiles.
- Silent update: cancelled UAC leaves the download Ready (localized retry
  banner) instead of treating apply as success; local helper/IO failures map
  to `ConfigurationFailure` rather than generic `ServerFailure`; HTTPS
  downloads reject non-HTTPS redirects (except loopback).
- ODBC: rollback transactional batch before returning a connection to the
  pool; chunked `executeDirect` bulk is atomic; streaming session cache
  disconnects evicted sessions; cancel on the last chunk does not reuse a
  dirty session; parallel/BCP failures are `Failure` (possible partial
  writes called out). SQL Anywhere / SQL Server streaming still does not
  reuse sessions (`odbc_fast` 4.5.1 does not document that as safe). One RPC
  can own several handles (parallel read-only batch / bulk); cancel aborts
  all of them and quarantines that DSN until recycle recovers.
- Empty DB streams no longer leak streaming slots; `LazyString` ODBC cells
  are materialized before `rpc:response` encoding.
- SQL documentation comments (`--`, `/* */`) no longer fail validation; they
  are stripped before prefix and dangerous-pattern checks. Client tokens with
  global table/view scope ignore per-resource deny rules, matching the UI.
- GZIP receive decompresses incrementally under `maxOutputBytes`; excess
  expansion, size mismatch, or invalid gzip returns `CompressionFailure`
  without tearing down the socket.
- `agent.getHealth` and ODBC recent-event snapshots expose only stable codes,
  command class, and duration (never SQL, parameters, connection strings,
  native ids, or raw driver messages).
- Tray icon activation reacts to mouse-up only, avoiding duplicate window
  restores.

## 1.8.6 - 2026-07-07

### Added

- Silent auto-update P0 fixes: resolve stale `PendingSilentUpdateDownloaded`
  on each check, refresh the app PID at apply time, and auto-apply staged
  installs after download (default on; opt out via `AUTO_UPDATE_AUTO_APPLY`
  or Settings > Updates).
- Settings toggle for automatic silent-update apply and metrics for
  auto-apply success/failure.
- ODBC P0/P1 hardening: circuit breaker, cancel paths, pool audit, benchmarks,
  and Playground policy gates.
- SQL auto DB streaming, TOP/pagination hardening, and RPC streaming limits.
- Transport extensions per hub ADR 0009–0011 (delivery guarantees, chunk
  streaming, coalesced acks, schema warm-up).
- Bootstrap orchestration with startup session and structured error logging.

### Changed

- Removed the UAC gate from the silent-update probe stage; elevation consent
  is evaluated at apply time instead of blocking downloads.
- Defaulted `enableSocketDeliveryGuarantees` to `true` so the agent always
  emits `rpc:request_ack`. The hub arms a 1 s ack-retry timer
  (`SOCKET_AGENT_ACK_TIMEOUT_MS`); without acks the agent re-parsed,
  re-validated, re-verified and re-dispatched every long SQL twice, wasting
  CPU and ack slots. Operators relying on the legacy "no ack" behavior can
  still flip the flag off via settings. See
  `plug_server/docs/plug_agente/03_performance_roadmap.md` item 1.
- Defaulted `enableSocketStreamingChunks` to `true` so the agent can negotiate
  ordered chunk streaming with hubs that advertise `streamingResults`. Small
  result sets continue to flow as a single `rpc:response`; only payloads
  above `HUB_STREAMING_ROW_THRESHOLD` switch to chunks, lowering peak RAM and
  TTFB on large queries. See `plug_server/docs/plug_agente/03_performance_roadmap.md`
  item 2.
- Raised the agent-advertised `recommendedStreamPullWindowSize` default from
  `1` to `8` so the hub starts streaming with enough in-flight credits to
  saturate the link without a round-trip per chunk. The new ceiling is still
  `maxBackpressureChunkQueueSize`. Tunable per deployment via the env
  `AGENT_STREAM_PULL_WINDOW_RECOMMENDED` (positive integer). See
  `plug_server/docs/plug_agente/03_performance_roadmap.md` item 6.
- Coalesced inbound `rpc:request_ack` emission. Bursts of `rpc:request` are
  buffered and flushed as a single `rpc:batch_ack` after a 5 ms debounce
  (cap of 32 ids, mirroring `HUB_MAX_BATCH_SIZE`); single-request flushes
  preserve the canonical `rpc:request_ack` shape. The hub already accepts
  both forms. See `plug_server/docs/plug_agente/03_performance_roadmap.md`
  item 3.
- `RpcResponsePreparer.prepareForSend` now preserves a propagated
  `meta.request_id` set by `attachRequestTrace` instead of overwriting it
  with `response.id`. Today's behavior is unchanged (`response.id ==
  meta.requestId == hub_uuid`); the change is preventive for the future
  `clientRequestIdEcho` extension where `response.id` carries the consumer
  id and `meta.request_id` must remain the wire correlator. See
  `plug_server/docs/plug_agente/03_performance_roadmap.md` item 8.
- `TransportSchemaLoader.loadAll()` now exercises a sentinel `validate(...)`
  call against the hot RPC schemas (`payload-frame`, `rpc.request`,
  `rpc.response`, `rpc.error`, batch variants) right after compilation.
  Schemas were already eagerly compiled at boot via `service_locator.dart`;
  this extra pass pays any one-time JIT/inline-cache cost upfront so the
  first request after a reconnect does not absorb that latency. See
  `plug_server/docs/plug_agente/03_performance_roadmap.md` item 9.

- `release.yml` now prefers the `RELEASE_PUBLISH_TOKEN` secret (PAT with
  `repo` scope) when publishing the GitHub Release. Releases created with
  the default `GITHUB_TOKEN` do not propagate the `release.published`
  webhook to downstream workflows, which forces `update-appcast.yml` to be
  dispatched manually. The workflow falls back to `GITHUB_TOKEN` with a
  `::warning::` when the secret is missing. See
  `docs/install/release_guide.md` for the setup procedure.

### Fixed

- Hub persistent reconnect survives transient hard relogin without dropping
  the long-lived session.
- `main()` runs Flutter bootstrap inside a guarded zone for clearer crash
  diagnostics.
- SQL Server and SQL Anywhere row-major streaming, 256 MB buffer cap, and
  connection-failure hints.
- Release preflight and appcast unittest paths after the `tool/` layout move.
- CI: pin Windows jobs to `windows-2022` for VS toolchain compatibility.

## 1.8.2 - 2026-06-01

### Fixed

- Windows auto-start repair now removes legacy `HKLM` / WOW6432 duplicate Run
  entries via elevated PowerShell registry cmdlets, reports partial success
  when HKCU is healthy but machine-scope cleanup needs UAC, and exposes
  startup diagnostics in Config preferences.
- SQL RPC responses omit null optional fields so hub JSON Schema validation
  no longer fails on nullable properties sent as explicit `null`.
- RPC idempotency replay now returns the same sanitized result map instance
  stored on the first success, so replayed agent action payloads match byte
  for byte on the wire.

### Added

- Update notification preferences and manual-only silent update mode in
  system settings.

### Changed

- Inno Setup startup task registers only in `HKCU` to avoid duplicate Run keys
  with the in-app auto-start service.

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
