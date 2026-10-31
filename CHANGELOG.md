# Changelog

All notable technical changes to Plug Agente are tracked here. Release process
and version bump instructions remain in `docs/install/release_guide.md`.

Version headings track application versions, not RPC or schema versions.
`tagged` means Git evidence only; `local` means untagged preparation.
`prepared` is reserved for reviewed release notes and does not authorize release.
Changes after a recorded snapshot stay in Unreleased.

## Unreleased

- Remote execution history shows admitted stdin bytes and confirmed pipe writes separately.

- Edit public catalog descriptions and diagnose remote I/O for the selected action and current hub connection.

- Add paginated discovery of authorized saved I/O actions, with an explicit list scope and Client-bound cursors.

- Add an off-by-default remote ad-hoc preference without expanding RPC contracts, authorization or release gates.

- Add explicit remote-action and process I/O opt-ins under System Actions preferences, with persistence errors and restart guidance; authorization and production gates remain unchanged.

- Bound installer preparation client waits and preserve unknown outcomes without replay or forced application termination.
- Validate feed keys through payload checks and installer-bound local packaging evidence instead of plaintext scanning of compressed setup bytes.

### Added — faithful remote action I/O

- Connect saved, locally approved actions to incremental binary stdin/stdout/stderr
  through negotiated agentActions.io v1, with durable encrypted receipts, ordered
  close, resumable reads, quotas and recovery without automatic replay.
- Require current local Client binding, scopes, allowlists and approval fingerprints;
  integrate lifecycle shutdown, bounded Windows workers and isolated long reads.
- Add localized faithful-mode configuration, independent execution/input/capture
  states and explicit byte-preserving downloads. Preserve legacy contracts.
- Add shared hub fixtures, native/crash/disk-full tests and private desktop
  acceptance tooling. Consolidate operational documentation and repair links.
- Keep I/O disabled by default. Development acceptance does not override the
  coordinated persona-v2 or installer/publication gates.

### Fixed — crash-test execution

- Resolve the Dart CLI when crash-journal tests run under Flutter, instead of
  launching `flutter_tester` as a CLI and leaving the release gate waiting.


### Changed — release history validation

- Reconstruct missing version entries from Git and validate version, build,
  chronology and release-note readiness before publication.

## 1.8.9 - 2026-10-26

Status: local
Build: 1.8.9+1
Source: 51177d52b3c573527b5e5d53b5468f466dd30bd7

- Reduce action UI resource usage and prepare the manual installer.

Version preparation is recorded in Git; no matching release tag exists. This
entry does not certify packaging, publication or production acceptance.

## 1.8.8 - 2026-10-25

Status: local
Build: 1.8.8+1
Source: 46a0408c0a353ca71397e93840094e65f7318045

- Harden ODBC queues, pagination and transaction lifecycle.

Version preparation is recorded in Git; no matching release tag exists. This
entry does not certify packaging, publication or production acceptance.

## 1.8.7 - 2026-10-24

Status: local
Build: 1.8.7+3
Source: aa6647744537044566b9ba11341e2b03d3420a0a

Packaged locally as `installer/dist/PlugAgente-Setup-1.8.7.exe` from
`1.8.7+3`. Appcast publication remains pending. This build has no
Authenticode signature, and automatic application remains blocked.

### Fixed — action process capture

- Ordinary execution drains stdout and stderr outside the UI isolate and
  forwards only the bounded prefix. A timeout keeps the partial capture, and
  stdin injection stays available.
- Stdin injection uses the same native pipe path, so its output stays off the
  calling isolate. A failed pipe close preserves the original read error.
- Windows pipe reads use the system CRT in binary mode. End of stream stays
  distinct from a native read failure, and a single owner holds the handle.

### Fixed — action process limits

- Each newly started local or elevated action tree can take a CPU limit from
  1 to 100 percent. Zero leaves Windows scheduling unchanged. Live process
  status is reported for both paths.
- The Windows job enforces the process memory limit, and output readers are
  released when the process ends.

### Fixed — elevated helper SQLite

- The elevated helper loads a pinned SQLite library from beside its executable
  by absolute path, instead of searching `PATH` or the working directory.

### Performance

- Large SQL results skip repeated column scans and extra byte copies during
  normalization, compression, and payload signing.

### Fixed — isolation and real installer asset checks

- Private native derivations also namespace the update-helper mutex and refuse
  unchanged Git bytes that omit required fixture transformations. Fixture-only
  installers disable Restart Manager application closing.
- The real UAC trial exposed the bootstrap refusing the installer's asset check.
  The derived bootstrap now runs the existing asset check before fixture startup,
  while normal launches remain blocked without private context. The failed
  namespace was uninstalled. A fresh UAC round passed nine administrative stages
  and nine non-elevated groups, with private residual cleanup and unchanged
  operator inputs. Automatic apply/probation/rollback and release stay blocked.

### Fixed — stale evidence in installed fixture acceptance

- Refuse old standard-user phase artifacts before installer dispatch. Bind each
  handoff/result to the exact fixture and attempt, claim once before IPC and
  require all nine checks without duplicates. Publish complete terminal JSON by
  non-overwriting Windows rename and reject resume after administrator exit.
  No installation, native authorization or production gate is bypassed.

### Added — verified compiled bootstrap input

- Verify the explicit application-build proof twice before allocating a private
  protected temporary workspace. Return only fixture paths/identity/hash; no
  operational profile or registration access. Persistent-Hub cold/restart
  validation is documented separately from installed update/recovery acceptance.

### Added — private C++ runtime for isolated source builds

- Extract only the named AMD64 runtime DLLs from an explicit cached Microsoft
  package into a new owned fixture, checking signatures, versions and hashes.
  No MSI installation or Windows/Visual Studio mutation occurs. Explicit
  --runtime-manifest selects a generated bound CMake redist path; the existing
  compatibility guard stays active and output must contain those exact DLLs.

### Added — explicit application proof in private packages

- Optional --application-build binds the exact verified proof, identity and
  application files before packaging and at lifecycle phase boundaries; invalid
  explicit proofs never fall back to stock Release. Only the named updater tools
  may be rebuilt with the fixture public key. Reports separate application
  source verification from whole-installer and installed acceptance; old
  bytes_only fixtures are not promoted. Real source-bound packaging remains
  pending a successful application build on a compatible C++ toolchain.

### Added — isolated bootstrap source build

- Export a full explicit ancestor commit into a private short build root, verify
  Git blobs and reviewed bootstrap/native isolation, use offline locked
  dependencies and published native cache, then bind the fresh application
  source/payload inventories. This does not qualify the existing bytes-only
  lifecycle package or enable installation/production. Full build validation is
  pending correction of the local Visual C++ redistributable/compiler mismatch.
- Preserve SYSTEMDRIVE in the restricted build environment for MSBuild
  FileTracker and quote Flutter batch paths with spaces; reject shell operators
  in build arguments. Windows CI includes the new source/proof regressions.

### Fixed — concurrent fixture evidence

- Serialize RPC metadata appends in the isolated chain observer. Concurrent
  Windows file handles could overwrite/interleave JSON records, invalidating
  SQL call counts and cascading into otherwise unrelated acceptance scenarios.
  Write failures remain visible and block subsequent evidence writes; no SQL,
  policy, journal or production runtime behavior changes.

### Fixed — isolated installer lifecycle evidence

- Format-2 fixtures bind the complete payload inventory and canonical SHA-256
  tree, including all installer executables. Modified/missing/extra/linked
  payload files and absent historical supervisors fail before phase dispatch.
  Inputs are rechecked at phase entry/exit; failed verification invalidates
  evidence without claiming rollback or authorizing retry. Historical fixture
  files are not rewritten. Hash binding is bytes_only, not source-build proof.
- Read-only --phase inspect verifies owned fixture artifacts without elevation
  or machine-change authorization. It reports installedState:not_checked and
  buildSourceVerified:false; it never inspects operational profiles or claims
  installed qualification. Existing install phases retain explicit authorization.


- Historical supervisor fixtures require an explicit full ancestor commit with
  disabled recovery contract 1, instead of implicitly selecting the current HEAD.
  Incompatible history fails before fixture creation; no checkout or fetch occurs.

- Reject external manifests and artifact paths before reading their contents;
  enforce owned non-linked fixture roots, size/format/hash checks and disabled
  production activation. Existing or external build outputs fail before creation.

- The namespaced Windows lifecycle runner no longer requires or opens an
  operational configuration database, vault, updater policy or executable set.
  Its host check compares Windows registration metadata only; fixture SQLite
  and DPAPI retention checks stay scoped to the fixture.
- Final verification failure or changed registrations invalidate the report.
  A successful check cannot promote an installation failure to success.
  The report explicitly distinguishes registration preservation from complete
  operational-installation preservation. Automatic apply and release stay blocked.

### Fixed — Windows vault concurrency

- O backend Windows local de flutter_secure_storage coordena processos por lock de arquivo com espera limitada, grava cifras em arquivo temporário antes de substituição atômica e preserva o cofre em erros de leitura/decifragem. Regressão isolada cobre 200 chaves concorrentes, timeout, morte do proprietário e arquivo inválido. Não habilita produção nem torna várias chaves uma transação; usuários antigos do cofre devem parar antes da atualização coordenada.

### Fixed — binary column type namespace

- Rich result metadata now identifies odbc_fast discriminants explicitly, preserving existing names/codes. The isolated three-engine companion adds read-only binary fixtures and metadata-only diagnostics. No production DDL, credential migration or release is authorized.


### Fixed — exact transactional resource authorization

- sql.operation.execute no longer authorizes homonymous resources by basename or reuses/overwrites legacy authorization decisions. Preserve other methods and global-scope semantics. Qualified DML, outputs and refusal paths are tested in dedicated fixtures; no existing grants/snapshots are enlarged. Production remains blocked.

### Added — durable SQL operation failure categories

- Add nullable failure_code in journal schema 3, preserving upgrades from schemas 1/2 and old terminal records without inferred causes. Enumerated metadata survives restart/get/duplicates; generic failures never expose native diagnostics.
- Carry optional failureCode through RPC/OpenRPC; it does not establish commit/rollback, permit replay or release deployment. Hub 1.15.0 and MCP retain the same safe code.

### Added — structural SQL operation foundation

- Decode and hash optional expectedStructure, requiring explicit structureGuard v1 and source identity/schema/constraints negotiation. Check metadata read permission and verify on the dedicated ODBC connection before beginning the write transaction; count all fixed verification queries within 32 commands.
- Refuse drift and preserve terminal journal deduplication without business effects. Native fixture covers the four engines; shared DML publication in MCP remains pending; transport and durable refusal categories are implemented in development. Production remains blocked.

### Fixed — SQL Anywhere structural view inspection

- Inspect ordinary BASE/VIEW resources by SYSTAB.table_type_str. The previous numeric discriminator mistook materialized views for ordinary views and omitted real views. Enforcement remains unknown; no capability or permission is inferred.
- Extend the isolated MCP chain fixture to 16 paginated resources, explicit table/view policies, cross-page joins and fixed structural drift actions. Only the disposable operator companion performs DDL; production never accepts caller DDL. Release remains blocked.

### Fixed — coordinated persona-v2 acceptance

- Require shared-knowledge-and-compatibility in the installer/appcast guard and release manifest, aligned with all 14 MCP gates. No gates are accepted; production remains blocked.

### Added — persistent MCP chain agent fixture

- Use production Drift configuration/session/credential/token repositories and
  FlutterSecure adapters with the native Windows DPAPI backend, isolated to the
  temporary fixture support directory. No operational vault or plaintext fallback.
- Restart without bootstrap preserves credentials, config/token identities and
  all four journals; unknown operations stay non-executable after recovery.
  Desktop bootstrap/installer and complete release acceptance remain pending.

### Fixed — verified SQL in the MCP chain

- Strict sql.execute ingress accepts expectedSource v1; malformed identities
  remain invalid. Executing-connection checks and live policy still gate SQL.
- Verified materialized queries, including chunked delivery, explicitly report
  completeness without turning omitted legacy flags into proof. Preserve upstream
  truncation. Incomplete/mistyped remote profiles return typed validation errors
  instead of terminating a Socket.IO callback with unchecked casts.
- Add the explicit four-engine MCP/hub/agent companion with private fixtures,
  real ODBC/policy/journal, approval, revocation and post-commit confirmation loss.
  This does not certify full desktop/Prisma bootstrap or release acceptance.

### Fixed — ODBC decoder, connection cleanup and streaming

- Compressed columnar decoding in `dart_odbc_fast` releases native buffers
  through a Rust finalizer, removing the Dart callback that could abort the
  process. Explicit release detaches the finalizer; partial failures free the
  allocation, and older native libraries use a Dart copy with immediate release.
- Unique logical checkout IDs prevent a delayed pool return from removing a
  newer acquisition that reused the same native handle. Diagnostics distinguish
  active checkouts, pending returns and unknown outcomes without connection
  strings or credentials.
- Pending discards are registered before queue admission, coalesced and awaited
  with a timeout during shutdown, reload and recovery. Unconfirmed cleanup stays
  isolated; reconciliation does not issue a second return for a pending discard.
- Row-major streaming transfers completed batch lists without copying and maps
  only the next batch after the consumer finishes. Cancellation avoids mapping
  future batches; eager helpers, columnar streaming and public contracts remain
  unchanged.

### Changed — reproducible native builds and performance validation

- Pin `odbc_fast` to Git revision
  `ea1e04f03a8cf1f2d5f3790697e8bc62ba130f89`. Native builds use the tracked
  `Cargo.lock`, `--locked` and SHA-256 manifests; Flutter hooks and packaging
  verify the corresponding DLL without manually changing the global Pub cache.
- Benchmark tooling uses warm-up, nine serial repetitions, alternating order,
  identical-code controls and temporary suspension prevention. Changes to
  source, harness or binaries invalidate measurements; intentional native
  dependency changes require explicit revisions and binary identities.
- Heap diagnostics collect post-GC checkpoints without retaining allocation
  reports. Unstable controls, insufficient samples and zero heap baselines are
  inconclusive; existing performance thresholds remain unchanged.
- Validation passed 4,800 offline application tests, 1,881 Rust tests, 1,873 SDK
  Dart tests, static analysis, Windows Release build and integration on SQL
  Server and SQL Anywhere. Ten stress rounds per database ended with zero active
  checkouts and confirmed cleanup.
- No batch/buffer tuning candidate qualified. Native streaming remained below
  the required 2x speedup (SQL Server: 0.253x; SQL Anywhere: 1.085x); unstable
  controls left relative performance approval inconclusive. Defaults and the
  baseline were preserved. Installation, upgrade and repair qualification on
  Server 2016/2019/2022/2025 and Windows 10/11 remains pending. See the
  [results and evidence](benchmarks/history/20261005_performance_corrections/REPORT.md).

### Added — Windows updater service foundation

- Native `PlugAgenteUpdater` supervisor, versioned worker and control client,
  with protected policy/journal/staging, local named-pipe IPC, client identity
  checks and publisher validation. Control binaries remain outside the agent
  bundle; workers use the full application version, including build number.
- Administrative enrollment and revocation for global installations.
  Interactive setup offers automatic updates; a new silent installation
  requires `/AUTOUPDATE=1`, while silent upgrades preserve existing approval.
  Per-user installations retain the manual update path.
- Signed release manifest contracts and shared Python/Dart/C++ verification
  fixtures. New feed entries bind the manifest URL, hash and signature;
  the client verifies this binding and the bounded HTTPS manifest before
  downloading the setup. Legacy feeds cannot authorize privileged application.
- Reversible SQL/action queue admission, maintenance coordination, SQLite
  checkpointing and exact current-user DPAPI secret snapshots, with regression
  coverage for IPC, integrity, ownership and uncertain recovery states.
- Service application remains disabled by `kApplicationContractImplemented=false`
  and `applicationContractValidated=false`. Session launcher, runtime maintenance
  integration, authenticated validation boot, complete rollback and Windows
  client/Server qualification remain pending; the active legacy helper can
  still request UAC. See the [current plan](docs/implemente/plano_auto_update_evolution.md).

### Fixed — Windows installation and silent updates

- The legacy helper derives installation scope from registered installation
  metadata, preserves custom directories and relaunches under the original
  user after confirmed setup completion, cancelled UAC or failure before setup
  starts. Silent apply uses `/LAUNCHAFTERUPDATE=0` and `/NOCLOSEAPPLICATIONS`.
- Installer supervision uses a 30-minute deadline instead of an infinite wait.
  Unknown, missing or stale post-dispatch status and `recoveryRequired` retain
  pending artifacts and ownership; timeout does not authorize another setup.
- Helper signature checks no longer reuse a successful result by file path.
  Privileged staging revalidates pinned files and ancestors and rejects reparse
  points, additional hard links and unconfirmed integrity.
- Installation scope controls `plugdb://` registration. Visual C++ runtime
  installation checks minimum version, Microsoft signature and exit status,
  recording a pending reboot without restarting Windows automatically.
- Recoverable dependency and configuration failures continue installation with
  warnings, required actions and a report opened on interactive completion.
  Core runtime and updater safety failures remain blocking. Optional repair can
  repeat configuration and diagnostics without recopying application files.
- Downloaded updates respect quiet hours and cooldown on automatic/shutdown
  paths. Explicit apply can bypass those windows, preserving integrity checks.
- Launcher-status tooling uses the canonical schema path; its regression tests
  are included in publication gates.

### Changed — release publication and documentation

- Production publication requires tests, Authenticode validation of all owned
  executables and the setup, and signed feed/manifest assets. Unsigned or
  verification-bypassed builds are limited to development/dry-run artifacts.
- Release publication calls the reusable appcast/deploy workflow directly,
  without a PAT or secondary release event. Shared publication is serialized;
  deployment and cryptographic smoke checks use the exact published feed commit.
- Channels propagate through build, installer and feed; prereleases use `beta`
  and cannot enter `stable`. Appcast entries are deduplicated by version,
  platform and channel and re-signed when a signing key is supplied. Asset
  selection requires the exact expected setup and validates HTTP responses.
- Removed the superseded action-MVP plan, delivered server checklist and their
  archive index; repaired references and removed the unsupported v1 payload
  example. Installation, release and security guides now distinguish the
  operational legacy helper from the incomplete service implementation.
- Consolidated the updater plan around current implementation, remaining work
  and qualification criteria, removing superseded rollback and hub-RPC plans.
  No new hub RPC methods are introduced.

### Fixed — Socket.IO transport lifecycle

- The shared transport worker pool settles queued and active jobs exactly once on disposal, closes reply ports/listeners, kills workers that finish startup after shutdown, and enters a deterministic failed state after startup failure or unexpected worker exit. Existing worker counts, thresholds and public codec error mappings remain unchanged.
- Stream idle expiry invalidates producers and releases queued chunks/completion. Registry timers and removal callbacks are tied to emitter identity, preventing an old instance from removing its replacement.
- Chunk admission always respects the existing queue ceiling. A single FIFO drain reserves credit before asynchronous send and emits completion once after the admitted chunks; transport loss prevents further flushing.
- Heartbeat preparation is marked before the first await and isolated by session epoch. Failed sends do not arm ACK timeouts; asynchronous exceptions are handled.
- Pulls, heartbeat ACKs and heavy overload identity extraction use the existing asynchronous decoder. Independent per-session control sequences retain arrival order and discard stale results after disconnect or session replacement.

### Added — communication regression coverage

- Internal aggregate diagnostics for worker occupancy/wait/failure/cancellation, emitter expiry and queue peak, heartbeat preparation and control decode. No new fields in public socket events or health snapshots.
- Deterministic send/startup gates, controlled-clock lifecycle tests including 20,000 expiry cycles, and a fixture generated by the production Dart columnar encoder.
- Required sibling contract checks in cross-project CI, recorded revisions and nine-repeat codec comparisons with compatibility checks and unchanged p95/throughput limits. RSS is reported separately; Dart heap validation remains pending.

### Changed — communication documentation

- The standard, binary transport guide, backlog and roadmap describe the corrected lifecycle, initial recommended credit of 12 and hub normalization of columnar chunks. `ODBC_STREAM_COLUMNAR_WIRE` can already emit empty `rows` with columnar content without wire-only mode.
- Profile 2.11.2, accepted framing and legacy compatibility remain unchanged. Rollout is pending relative performance gates, full repository validation and representative staging measurements; the hub synchronization matrix records the coverage boundaries.

### Changed

- Hub extensions reference ADRs 0009, 0011 and 0012; optional health polling
  remains disabled by default. Superseded server implementation documentation
  and the delivered checklist have been removed.
- Visao geral e roadmap de comunicacao sem a secao e a linha que repetiam health e o estado atual.

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
- Installer installs Visual C++ Redistributable x64 when missing or below the
  required version and registers `plugdb://` according to installation scope
  (removed on uninstall).

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
- Inno silent updates wait for the app pre-close budget (helper PID wait ≥ 70s).
  The original-user helper owns relaunch; `[Run]` and Restart Manager do not
  relaunch the agent on this path.
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
  (`SignedUninstaller=yes`); interactive setup uses `CloseApplications=yes`,
  while silent updates require cooperative exit and disable setup app closing.
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

Status: tagged
Build: 1.8.6+1
Source: 865a3d074e37fe28696d9a65e78e8151e179eb93

Git tag `v1.8.6` is verified; publication status is not inferred from the tag.

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

## 1.8.5 - 2026-06-11

Status: tagged
Build: 1.8.5+1
Source: fafc6a64955679daefd34031931f3ffdd1377cb8

Git tag `v1.8.5` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.8.4`.

- fix layer boundaries + lint after god-class refactors
- Split god-class modules into focused health builders, ODBC executors, playground sessions, and agent-action save handlers to clarify layer boundaries and ease testing.
- Migrate operational tooling to Python, split large modules, and tighten bootstrap/core boundaries.
- Split boot, hub, and ODBC orchestration for clearer lifecycle and layer boundaries.
- Refactor agent actions execution, presentation, and RPC boundaries.

## 1.8.4 - 2026-06-04

Status: tagged
Build: 1.8.4+1
Source: b372df8c46e4278bd558816fb28e476a5ab447a8

Git tag `v1.8.4` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.8.3`.

- fix(release): early preflight without Flutter on CI
- feat(auth): proactive hub JWT refresh and hardened HTTP session renewal
- feat(release): add local publish gate and harden CI workflows

## 1.8.3 - 2026-06-02

Status: tagged
Build: 1.8.3+1
Source: 1f0c029c1b631c2086153a2fa0c35ef9cd048671

Git tag `v1.8.3` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.8.2`.

- style: sort imports for release analyze gate
- fix: unblock release tests for storage health and websocket UI
- feat(storage): harden ProgramData ACL, scheduler lock, and ops visibility
- feat(ui): improve update check feedback and message modals

## 1.8.2 - 2026-06-01

Status: tagged
Build: 1.8.2+1
Source: 0c0553880ead0988b8f72555e92f053dc01dee26

Git tag `v1.8.2` is verified; publication status is not inferred from the tag.

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

## 1.8.1 - 2026-06-01

Status: tagged
Build: 1.8.1+1
Source: 73a3b0c479a24d9ba1d8a8d2b979e420066a8b31

Git tag `v1.8.1` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.8.0`.

- fix: robustecer autostart no Windows
- Harden RPC SQL transport handling
- fix: harden rpc sql streaming flow and add codcliente e2e
- feat(agent-profile): sync hub catalog on save with conflict and retry UX
- fix(config): audit settings UX and surface failed restore on backup tab

## 1.8.0 - 2026-05-28

Status: tagged
Build: 1.8.0+1
Source: 5c763239b49d26b43e475d59608077e8cda6f6f5

Git tag `v1.8.0` is verified; publication status is not inferred from the tag.

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

Status: tagged
Build: 1.7.2+1
Source: 71929e0978a9708ba5ec51848d35ad25b8d2a402

Git tag `v1.7.2` is verified; publication status is not inferred from the tag.

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

## 1.7.1 - 2026-05-28

Status: tagged
Build: 1.7.1+1
Source: a886aafa167b380e77b244f953122852bc71a4f2

Git tag `v1.7.1` is verified; publication status is not inferred from the tag.

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

Status: tagged
Build: 1.7.0+1
Source: d79870de568362ed18cf406af78f53a2e7f5e360

Git tag `v1.7.0` is verified; publication status is not inferred from the tag.

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

## 1.6.9 - 2026-05-23

Status: tagged
Build: 1.6.9+1
Source: a7fafce987f2f7e1d3f784bb2cae466498774f1b

Git tag `v1.6.9` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.8`.

- test: isolate Data7 launch access checks
- fix: resolve agent actions analyzer issues after editor refactor
- refactor: integrate agent actions page, provider, and test improvements
- refactor: split agent actions page and extract provider filter helpers
- fix: repair UTF-8 mojibake and refine agent actions UI

## 1.6.8 - 2026-05-23

Status: tagged
Build: 1.6.8+1
Source: f53b6c5cbc6476b75f4eeb19f34e62433a8d6271

Git tag `v1.6.8` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.7`.

- feat(hub,transport): resilience phases 1-3, batch RPC phase 3, async benchmark
- feat(transport): JSON-RPC batch parallel Phase 2
- feat(transport): optional protocol and dispatch improvements
- Harden Plug Socket.IO transport after audit by introducing domain ports, splitting inbound RPC handling, and mapping failures with Result at the frame boundary so hub resilience and throughput improve without leaking transport details.
- feat: align live Hub E2E validate, CI, and signing tooling

## 1.6.7 - 2026-05-14

Status: tagged
Build: 1.6.7+1
Source: d6ae9b12a970f4ca4d2a5faf1e6c44546556792f

Git tag `v1.6.7` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.6`.

- docs: update sql queue concurrency tuning guidance
- feat: tune odbc async worker pool
- feat: add native bulk insert path
- feat(health,odbc): extend agent-get-health contract and ODBC pool observability
- Improve ODBC SQL performance controls

## 1.6.6 - 2026-05-12

Status: tagged
Build: 1.6.6+1
Source: e534893e038168025d5737541fde2fd0754871ea

Git tag `v1.6.6` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.5`.

- Improve release automation
- Fix startup minimized autostart handling

## 1.6.5 - 2026-05-12

Status: tagged
Build: 1.6.5+1
Source: 8d7c8f7b94762800ed2d41ba4d24e31f4d7866e7

Git tag `v1.6.5` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.4`.

- Improve profile snapshot metrics caching
- Align communication profile 2.9

## 1.6.4 - 2026-05-08

Status: tagged
Build: 1.6.4+1
Source: d0bddb753db7c0f6a3222c2ea5fee64e53e6f8d7

Git tag `v1.6.4` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.3`.

- Improve socket protocol readiness handling

## 1.6.3 - 2026-05-08

Status: tagged
Build: 1.6.3+1
Source: 1ea11c130db76bda598612f192a7e048920b6b79

Git tag `v1.6.3` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.2`.

- fix(auto-update): dedupe manual update UI and diagnostics

## 1.6.2 - 2026-05-08

Status: tagged
Build: 1.6.2+1
Source: baad4f558dbefda474d88d306922fd2b1cc5bdba

Git tag `v1.6.2` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.1`.

- chore: bump version to 1.6.2

## 1.6.1 - 2026-05-08

Status: tagged
Build: 1.6.1+1
Source: bb3400f06318841951979e9693f233d1c4b51097

Git tag `v1.6.1` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.6.0`.

- test: fix async fallback prepare timeout verification after pool acquire
- Improve ODBC queue reliability and diagnostics
- feat(auto-update): add diagnostics and feed validation workflow
- feat(config): refine client token UX and update readiness
- Harden client token authorization flow

## 1.6.0 - 2026-05-07

Status: tagged
Build: 1.6.0+1
Source: 5b35c211942d3c8ceca2a7b5bf1116d7a85edef0

Git tag `v1.6.0` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.5.3`.

- fix(appcast): remove stray UTF-8 BOM from 1.5.3 release notes
- feat(config): backup/restore hardening, hub agents timeout, query checks
- feat(config): split settings into three tabs and add local backup/restore
- feat: add granular global client token permissions

## 1.5.3 - 2026-05-04

Status: tagged
Build: 1.5.3+1
Source: 095a63386290d541f6f6dd4be365b7acea31b6fa

Git tag `v1.5.3` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.5.2`.

- feat(updater): harden windows auto-update for 1.5.3

## 1.5.2 - 2026-05-04

Status: tagged
Build: 1.5.2+1
Source: 385521f15df269ed32210876869d42c777f08e05

Git tag `v1.5.2` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.5.1`.

- chore: ship ODBC fixes and bump 1.5.2
- feat(hub): persistent retry caps for offline probe, recovery_id, relogin cooldown, reconnect UI hints
- feat(resilience): correlate hub recovery logs with recovery_id
- feat: hub resilience, ODBC hardening, and failure mapping
- chore(rules): update Cursor programming rules and AGENTS entry

## 1.5.1 - 2026-05-01

Status: tagged
Build: 1.5.1+1
Source: aa89ab097b2db90a98da9eb9fd6245b7f1b377f8

Git tag `v1.5.1` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.5.0`.

- chore(release): 1.5.1

## 1.5.0 - 2026-05-01

Status: tagged
Build: 1.5.0+1
Source: 92213d8ab3a7c2d41afb959e9248e737ecd75c45

Git tag `v1.5.0` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.4.0`.

- chore(release): 1.5.0
- feat(config): client token flow updates and lint fixes
- feat: SQL investigation feed, ODBC batch context, and E2E env tooling
- fix(odbc): align SQL RPC contracts and harden concurrency behavior
- feat(recovery): harden hub reconnect and session recovery

## 1.4.0 - 2026-04-28

Status: tagged
Build: 1.4.0+1
Source: f1cd3297e288dd769f6b722fc9499b71266be4d7

Git tag `v1.4.0` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.3.2`.

- chore(release): 1.4.0
- feat(rpc): add agent.getHealth with contract and protocol 2.9
- fix(health): report real process uptime via AppUptime
- feat(odbc): SQL execution queue, circuit breaker, and reliability hardening
- chore(ci): update GitHub Actions versions

## 1.3.2 - 2026-04-27

Status: tagged
Build: 1.3.2+1
Source: 43fb4305c7b5d246a15e04a871651e91a0ba48ed

Git tag `v1.3.2` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.3.1`.

- fix(database): make token name migration idempotent
- ﻿fix(tests): fix 3 CI test failures introduced by reliability and feature commits
- chore: update installer and version constants to 1.3.1

## 1.3.1 - 2026-04-27

Status: tagged
Build: 1.3.1+1
Source: 7ef1189ef504014adf2b80077762fb71dd19e7d6

Git tag `v1.3.1` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.3.0`.

- fix(hub): reconnect token refresh during recovery burst
- ﻿fix(client-token): fix scrollbar overlap and use token name as export filename default
- ﻿feat(client-token): add user-defined name field for token identification
- ﻿feat(client-token): add multi-table rule entry, file import/export and duplicate handling
- ﻿fix: reliability and correctness improvements across transport, ODBC, application and presentation layers

## 1.3.0 - 2026-04-26

Status: tagged
Build: 1.3.0+1
Source: 877a2175e571b976605b82549ef5ccf6652786af

Git tag `v1.3.0` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.2.6`.

- feat(e2e): hub socket, DML perf/bulk integration tests and transport updates
- feat(odbc): harden query execution, validation, and cancellation
- fix(hub): recover after io server disconnect; guard WebSocket config actions
- chore: installer robustness and auto-update reliability
- fix(ci): align SQL validation RPC test with sqlValidationFailed

## 1.2.6 - 2026-04-14

Status: tagged
Build: 1.2.6+1
Source: a38163676b9a6e0c21ee87ab80383aa3bc4029fd

Git tag `v1.2.6` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.2.0`.

- feat(hub): reconnect resilience, lifecycle sync, and configurable persistent retry
- docs(communication): OpenRPC 2.7.0 with client_token.getPolicy method
- feat(rpc): client_token.getPolicy introspection, rate limits, and profile 2.8
- feat(rpc): align DB connection errors with JSON-RPC catalog (v1.2.3)
- feat(l10n): migrate UI from AppStrings to ARB and AppLocalizations

## 1.2.0 - 2026-03-26

Status: tagged
Build: 1.2.0+19
Source: 722f2c8637a62e701c2be32999f6b6b1ad214393

Git tag `v1.2.0` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.1.2`.

- feat(auto-update): HTTPS appcast flow without DSA/WinSparkle

## 1.1.2 - 2026-03-26

Status: tagged
Build: 1.1.2+18
Source: e2d5e5d57d79362d30da5b886b42b7cce80a928d

Git tag `v1.1.2` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.1.1`.

- release: bump version to 1.1.2+18
- feat(protocol): agent.ready schema, capabilities and socket transport v2
- feat(benchmarks): transport metrics, PayloadFrame suite, ODBC strategy doc
- feat: Plug protocol hardening, perf/reliability, and docs parity

## 1.1.1 - 2026-03-23

Status: tagged
Build: 1.1.1+17
Source: dcdb5967b447abb40f9b67604027746d1ad57450

Git tag `v1.1.1` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.1.0`.

- perf: RPC canonicalization, ODBC streaming/pool, validation, UI
- perf: transport compression, RPC validation, ODBC and benchmarks
- feat(odbc): lease pool TTL, warmup, benchmark baselines, and RPC diagnostics
- feat(codecs): gzip via dart:io, PayloadEncodingFailure, row compressor tuning
- test(benchmark): socket E2E baseline parity and optional micro-benchmarks

## 1.1.0 - 2026-03-20

Status: tagged
Build: 1.1.0+16
Source: 63eda21df4262c17a62d32471e89a6c0de8c1673

Git tag `v1.1.0` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.14`.

- chore(release): bump version to 1.1.0+16
- docs(communication): sync standard with transport flags and -32013 semantics
- feat(socket): protocol alignment, outbound compression auto, perf improvements
- feat(transport): async framing, isolate decode, full stream chunk validation
- feat: PRR improvements, ODBC/JWKS refactors, lint and tests

## 1.0.14 - 2026-03-18

Status: tagged
Build: 1.0.14+15
Source: d94eadb629d10f93658f63cfaab05105b8fb8104

Git tag `v1.0.14` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.13`.

- Improve auto-update reliability and diagnostics

## 1.0.13 - 2026-03-18

Status: tagged
Build: 1.0.13+14
Source: 5d66c2023e443d4f286a14e3eadb5d20827da77a

Git tag `v1.0.13` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.12`.

- fix: resolve GetIt recursion for metrics interfaces
- refactor: apply code quality improvements (rodadas 5-6)
- feat: migrate global settings storage and bootstrap hardening
- refactor: Clean Architecture, error handling, and robustness improvements

## 1.0.12 - 2026-03-18

Status: tagged
Build: 1.0.12+13
Source: 651928ece0f20693398467a028b3b0477890fe9c

Git tag `v1.0.12` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.11`.

- feat: auto-update improvements and performance/reliability enhancements
- fix(update): use full version (1.0.11+12) in appcast to fix false update prompt
- feat(communication): add batch execution order and reliability improvements

## 1.0.11 - 2026-03-18

Status: tagged
Build: 1.0.11+12
Source: 0fde5e9caf951dc7cecf0cf94208a85723cda4b3

Git tag `v1.0.11` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.10`.

- fix: correct DSA signature in appcast for 1.0.10

## 1.0.10 - 2026-03-18

Status: tagged
Build: 1.0.10+11
Source: 118a5b2bc73507fab5594f9b6fcc1b979e7d4154

Git tag `v1.0.10` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.9`.

- fix(ci): replace dart sign_update with Python cryptography library

## 1.0.9 - 2026-03-18

Status: tagged
Build: 1.0.9+10
Source: 63ab567944718c3a8584ca94cc8cf20f9ce27796

Git tag `v1.0.9` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.8`.

- fix(ci): run workflow on Windows for sign_update (Linux unsupported)

## 1.0.8 - 2026-03-18

Status: tagged
Build: 1.0.8+9
Source: 43c72e9dde45f565ff564c6710365f993e899ed7

Git tag `v1.0.8` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.7`.

- fix(ci): use GitHub API URL for asset download with Accept header

## 1.0.7 - 2026-03-18

Status: tagged
Build: 1.0.7+8
Source: c26083ff3867925d0438d48fa3be9006d53ecb25

Git tag `v1.0.7` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.6`.

- fix(ci): robust DSA signature extraction and asset download

## 1.0.6 - 2026-03-18

Status: tagged
Build: 1.0.6+7
Source: bed53ea40c9d0892b6c090804bb6329aaa38f5fb

Git tag `v1.0.6` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.5`.

- fix(ci): use Flutter stable channel for Dart 3.10+
- fix(ci): use Flutter 3.35.x for Dart 3.10+ compatibility

## 1.0.5 - 2026-03-18

Status: tagged
Build: 1.0.5+6
Source: a17304a942a1bb3121a371ab98cfa99a0866ca5b

Git tag `v1.0.5` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.4`.

- chore: bump version to 1.0.5

## 1.0.4 - 2026-03-18

Status: tagged
Build: 1.0.4+5
Source: 19645c9389d5e5d6847d3c8476170295e5bbab5a

Git tag `v1.0.4` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history since `v1.0.3`.

- chore: add DSA public key for WinSparkle signature verification

## 1.0.3 - 2026-03-18

Status: tagged
Build: 1.0.3+4
Source: 4ab3377dfc72ff03239a60be3ed4c0289eb8ea9f

Git tag `v1.0.3` is verified; publication status is not inferred from the tag.

Reconstructed from the Git history.

- chore: harden auto-update workflow and installation docs
- chore: padronizar documentacao em lowercase e atualizacoes diversas
- feat: atualizar ícones do app com plug_connect-blockchain
- chore: atualiza ícones do app com nova imagem (database + plug)
- feat(websocket): improve reconnection resilience and retry policy
