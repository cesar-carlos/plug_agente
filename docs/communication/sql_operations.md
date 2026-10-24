# SQL operations: journal and transaction integration

Current scope: PostgreSQL, SQL Server and SQL Anywhere. Firebird cases and
four-engine matrices in dated sections are retained as historical evidence;
Firebird is no longer supported. Current acceptance requires the three-engine
matrix and all gates in the [release manifest](../../contracts/persona-v2-release.json).
Production publication remains blocked. Never retry an unknown operation.

For physical identity and structural inspection, see
[source discovery](source_discovery.md).

## Concurrent chain evidence

The isolated chain observer serializes metadata file appends before returning
each RPC response. Windows concurrent append handles must not lose/interleave
records used to count dispatches. A failed write remains a fixture failure and
blocks later writes; malformed or missing evidence is never ignored to pass a
test. This changes only the observer, not SQL execution, journals or authority.
The regression uses a private temporary file and concurrent delegated responses.

The agent now registers `sql.operation.execute`, `sql.operation.get` and
`sql.operation.cancel` in the dispatcher. Production installer/appcast publishing
remains blocked by contracts/persona-v2-release.json. The hub forwards only after
sqlOperations version 1 negotiation. Legacy sql.executeBatch is not a substitute.

The agent's response ACK retry mechanism is distinct from hub request replay:
`sql.operation.*` responses are not in the `sql.execute`/`sql.executeBatch` ACK
bypass set. Clients must tolerate duplicate response delivery without repeating
execution. The [contract review backlog](socket_communication_backlog.md#contract-review-findings-2026-10-24)
also records the compact operation/source error shape that currently fails the
structured outgoing error schema; it remains a blocker to full contract acceptance.

## Structural operation guard in development

Optional expectedStructure on sql.operation.execute is part of the locally
calculated content hash. It requires expectedSource and explicit negotiation of
sqlOperations.structureGuard:1, sourceSchema/sourceIdentity v1, and
sourceConstraints v1 when constraint expectations are supplied. Old peers do
not negotiate structureGuard implicitly; ordinary operations remain unchanged.
Metadata dependencies also require live read permission, in addition to DML.

The dedicated ODBC connection proves identity, checks fixed table/column and used
constraint metadata, then proves identity again before beginning the write
transaction. Metadata and extra identity statements count toward the existing
32-statement budget, including per-driver row-count queries. No business DDL,
reconnection, retry or extra connection is introduced. Structural mismatch
refuses before transaction begin. The durable intent remains terminal and a
repeat does not dispatch. Public receipts may include the optional durable
`failureCode`; older journal records can omit it. MCP adoption of that reason
for dependency suspension remains separate from agent receipt persistence.

This is agent foundation, not shared DML adoption in the MCP. Hub transport/capability forwarding and its coordinated 1.14.0 snapshot are
implemented in development. Qualified DML resources,
MCP publication/preparation and current dependency checks remain pending. The
native four-engine fixture validates columns and identity; it does not certify
all constraint variants, minimum engine privileges or persistent hub transport.
SQL Anywhere 16 now has scoped native proof, described below. Production release stays blocked.

## Executing-connection identity — 2026-10-11

75 real ODBC cases passed (17 PostgreSQL, 17 SQL Server, 17 SQL Anywhere,
24 Firebird), without skips. With expectedSource/sourceIdentity v1, the agent
checks complete native identity before SELECT and after reading on the same
dedicated connection; DML checks before transaction begin. Identity mismatch
prevents business SQL and journal duplicates cannot reexecute the operation.
SQL Anywhere locator is refused by this v2 path; legacy generated-output tests
do not certify its durable identity. Authority remains synthetic. Full live
hub/agent tests and release acceptance remain blocked.

## Earlier isolated dialect matrix — 2026-10-11

55 mandatory real ODBC tests passed: 12 PostgreSQL, 12 SQL Server, 12 SQL Anywhere
and 19 Firebird. MCP-compiled SQL Anywhere plans recover INSERT IDs and UPDATE
outputs by trained UNIQUE/identity reads on the same transaction and bind them
into later DML. No MAX(id), session-global identity or interpolated values.
Read permissions remain required for auxiliary steps. Their native count and
the fixed database proof remain within the 32-command budget.

The Firebird group additionally executes seven MCP-validated SELECTs using its
own parser: model, FIRST/SKIP, ROWS, aggregation, CONTAINING/CAST, LEFT JOIN and
empty validation envelope. Firebird 4/5 wide SUM results require explicitly
trained bounded decimal CAST with the tested ODBC driver. This is not silent SQL
rewriting or full numeric/trigger acceptance. The authority is synthetic; actual
JWT/ClientAgentAccess/policy/hub end-to-end acceptance remains pending. Publishing
and operation opt-in remain blocked/off respectively. See MCP validation docs.

## Negotiated transport and homologation opt-in

The agent omits sqlOperations by default. ENABLE_SQL_OPERATIONS=true seeds an
unset preference for a dedicated homologation environment; existing preferences
win. The live feature flag is checked again for every operation. Reconnect to
rebuild capability snapshots after changing it. This opt-in does not certify any
engine, approve a skill or unlock release.

Both peers require enabled:true, version:1, durableJournal:true,
singleSourceTransaction:true and automaticReplay:false. maxSteps, maxAffectedRows
and timeoutMs must be positive integers; their negotiated values are the minima
of both peers and platform ceilings (32, 100000, 300000). Plans exceeding them
are refused before journal/connection work, never rewritten.

Hub REST, agents:command and relay enforce the authenticated agent registration
and current ready socket before emission, including after queues/async encoding.
Old/missing/incompatible capability fails with CAPABILITY_UNAVAILABLE. Ordinary
queries retain their previous transport. SQL operations never enter ACK resends;
operation IDs, fingerprints, parameters, timestamps and journal states are preserved.
Required directlyAffectedRows:null survives wire validation and replay storage.
Timeout or disconnect after execute dispatch means SQL_OPERATION_OUTCOME_UNKNOWN,
retryable:false: get/reconciliation replaces blind resend. Cancellation is not rollback.

## Durable identity and startup

`SqlOperationJournalRuntime` opens a separate `sql_operations.db` in global app
storage. It acquires an exclusive owner lock, upgrades additively and recovers
interrupted records before transports accept work. Shutdown closes the journal.
WAL, synchronous FULL and a five-second SQLite busy timeout preserve acknowledged
intent. Existing agent configuration, tokens and business databases are not reset.

The authorized scope hashes hub origin, agent ID, technical token hash and logical
physical source. Native v2 source identity hashes `[hubOrigin,nativeIdentityHash]`;
expectedSource is included in journal scope and the independent content hash.
The old `[hubOrigin,agentId,database]` path remains only for unrelated legacy clients;
live database identity is proven on the dedicated connection before begin. ODBC currentCatalog is not authority: real drivers return empty/truncated hints. Fixed complete SELECTs use CURRENT_DATABASE() on PostgreSQL, DB_NAME() on SQL Server/SQL Anywhere, and MON$DATABASE_NAME on Firebird. Names match exactly; only absolute Windows Firebird paths normalize case/separators. Each
operation stores the supplied fingerprint AND a locally calculated SHA-256 of all
execution fields, excluding credential aliases. A reused ID cannot change scope,
SQL, parameters, outputs, conditions, limits or deadline. Duplicate calls return
the durable state without another connection or dispatch.

Schema 2 adds nullable `content_hash` to schema 1. Old rows remain readable and
cannot be reclaimed with a new content hash. Startup turns interrupted execution
and cancellation requests into `outcomeUnknown`, preserving terminal receipts.
Schema 3 adds nullable failure_code additively. The executor stores only an enumerated safe category, including SOURCE_STRUCTURE_MISMATCH and SOURCE_IDENTITY_MISMATCH; unknown native codes become SQL_OPERATION_FAILED. No native message or payload is persisted. Execute/get/duplicates preserve the same category; terminal cancellation requests do not rewrite it. Older terminal rows remain without a reason. Startup recovery marks interrupted executions SQL_OPERATION_INTERRUPTED without claiming their business outcome. A failure category is not proof of commit/rollback or permission to resend.

Unknown records never become executable through expiry or restart. Journal/audit
contain metadata only: no SQL, input/output values, credentials or connection strings.

## Transaction execution

The executor claims durably before opening a dedicated connection and one
read/write transaction. Automatic reconnect and query replay are disabled. Live
token policy must bind the current agent and a mandatory database. The policy,
source, credentials and cancellation state are revalidated before each step and
immediately before commit; no authorization decision cache is used on this path.
The maintenance gate drains admitted executions and refuses new work while closed.
Legacy disconnect cancellation does not control these transaction handles.

Up to 32 real SQL statements execute in order. Bindings are typed scalars or
declared outputs from earlier steps. Integer/decimal strings preserve precision;
binary floating-point outputs cannot silently satisfy a decimal contract. Scalar
outputs require exactly one returned row and the declared column/type. Returned
IDs are always bound parameters, never identifiers or interpolated SQL.

Every write has explicit direct affected-row bounds and the operation has a total
bound. Optional row conditions can represent preconditions/postconditions through
separate SELECT steps. All conditions and limits are checked before commit.
Missing/indeterminate counts never become zero. Trigger/cascade effects are not
claimed to be included in the direct count.

The initial native strategy requires complete `RETURNING` rows on PostgreSQL and
Firebird. SQL Server/SQL Anywhere use fixed `SELECT @@ROWCOUNT` immediately after
DML on the same connection. The database identity SELECT and these internal queries consume the 32-statement budget
and plan validation refuses overflow before business SQL. The initial mandatory matrix passed 48 real ODBC tests on PostgreSQL 17.11, SQL Server 2022 (16.0.4236.2), SQL Anywhere 16.0.0.2043 and Firebird 5.0.4. This is not full product acceptance: triggers, the complete type matrix and end-to-end authority/transport still need certification.

Unknown engines, drivers without prepared parameters, missing catalog proof or a
catalog differing from the requested database are refused before DML. An empty/truncated ODBC catalog hint never substitutes for the fixed query proof; missing/incomplete/mismatched proof refuses before begin.
ODBC attribute parsing preserves braced secrets, binds all database aliases and
rejects database strings containing attribute injection characters or edge whitespace. Validated database values are unbraced because SQL Anywhere DBN treats braces as part of the name; braced passwords remain untouched.

## Initial SQL subset

The statement guard supplements agent policy and the future immutable MCP package;
it is not a complete dialect parser or publication authority. SELECT conditions
and single-target INSERT/UPDATE/DELETE are supported. UPDATE/DELETE require WHERE.
Multiple tables use separate ordered steps in the same transaction.

Write joins/subqueries, CTEs, scripts, comments, DDL, procedures, external/unknown
functions, linked databases and names with more than schema/table are refused.
Output contracts cannot use `MAX(id)`. The exact published record identity,
concurrency predicate, recortes and business semantics remain the MCP compiler's
responsibility. Publication and end-to-end writing are still disabled.

## Outcomes and cancellation

Wire states: `executando`, `cancelamento_solicitado`, `concluida`,
`rollback_confirmado`, `resultado_desconhecido`, `cancelada`.
Cancellation requests are checked between steps and before commit; acceptance
does not confirm reversal. A commit already begun may still complete.

A failure before commit becomes confirmed rollback only after the driver confirms
rollback. Commit failure, lost confirmation and unconfirmed rollback remain
unknown. No dispatch/commit retry is performed. A timed-out native call retains
its connection admission slot until it settles; rollback/disconnect never race
the pending call. Cleanup after timeout is asynchronous and the connection is
never returned to a reusable pool. A separate journal cannot guarantee exactly
once commit; subsequent status/reconciliation must establish business outcome.

## Contract and remaining work

The three strict JSON schemas are bundled and mapped to RPC methods. OpenRPC
methods are wired into the hub allow-list/parity matrix. The optional extension
has its own version 1; the base profile remains 2.11.2.

The isolated Node/Dart harness runs the production Socket.IO transport over
loopback, real temporary SQLite journal and a deterministic transaction adapter.
It covers REST dispatch and relay, lost commit confirmation, duplicate operation
IDs, status/cancellation and exact durable receipt preservation. Run in the hub:
RUN_DART_SQL_OPERATION_TRANSPORT=true with FLUTTER_BIN pointing at Flutter, then
vitest tests/integration/sql_operation_dart_transport.integration.test.ts.
This test does not access user databases or certify ODBC engines.

The isolated real-engine matrix is implemented, as are the MCP operation
compiler, publication runner and trained reconciliation in development. Remaining
acceptance includes SQL Anywhere durable native identity, full live authority and
transport, complete dialect/type/trigger parity, default product composition,
retention/cleanup and full console journeys. Mocks do not satisfy these gates.

Tests cover actual SQLite persistence/upgrade/recovery and simulated ODBC failures,
RPC dispatch, live authorization, cancellation, duplicate claims, limits, exact
bindings, unknown commit, pending native cleanup, schemas and maintenance. No DML
is executed in configured user sources and no operational app is launched.

## Mandatory real-engine matrix

Run tool/homologation/sql_operation_four_engines_test.dart explicitly, using
PERSONA_SQL_FIXTURE_MANIFEST for four newly created private fixtures. It never
loads .env or configured sources. Missing engines/driver/connections fail; no
skips. The MCP scripts/run-four-engine-homologation.ps1 compiles synthetic
INSERT/UPDATE/DELETE commands with the real MCP compiler before invoking it.
Names must match se7e_persona_<12 hex>_test, and Firebird must use the matching
private fixture file. Only operation_fixture is recreated in those databases.

The matrix exercises real DML, direct counts, scalar ID binding, rollback,
revocation before commit, duplicate suppression and file-journal reopen.
Authority is synthetic. A lost-ACK case injects failure only after actual native
commit; state remains unknown and duplicate dispatch is prevented. This is not
a live hub/policy test. PostgreSQL/Firebird no-output commands receive a server
RETURNING constant in the prepared hash, without reading an additional column.
SQL Anywhere generated IDs use MCP-compiled trained auxiliary SELECTs. The
verified v2 path still refuses its locator-only identity. No acceptance gate or
production opt-in is enabled by these tests.

## MCP chain with isolated real databases

The MCP scripts/run-persona-chain-homologation.ps1 explicitly starts the hub
companion and tool/homologation/persona_chain_agent_test.dart. It exercises real
MCP composition, REST, Socket.IO/RPC, executing-connection identity, policy, ODBC,
SQLite journal, publication, Client approval, DML/outputs, rollback, cancellation,
consumer/technical revocation and published cross-engine queries. sql.execute
schema ingress accepts strict expectedSource v1. Verified complete results carry
truncated:false (including materialized chunking); upstream truncation remains true.
Legacy unrelated requests retain their optional flag contract.

Only private named fixtures are accepted. The default hub uses PostgreSQL/Prisma
and real ClientAgentAccess request/owner approval. The agent uses production
AgentConfigRepository, HubSessionStore, OdbcCredentialStore and token repository
on Drift, with FlutterSecure adapters and real Windows DPAPI. Only support-directory
lookup points at the private fixture vault; storage/encryption are not mocked and
legacy/operational vault migration is disabled. SQLite contains metadata, not raw
passwords/JWTs/tokens. Missing/corrupt secrets fail closed without bootstrap fallback.
MCP, hub and agent processes restart; ODBC/JWT bootstrap is removed before agent
recovery. Config/token IDs, publications and grants survive. A second agent
restart reads all four unknown journals through hub RPC; duplicate fixture plans
return the same executionId and unknown count without running business SQL again.
The legacy fixed-table operation evaluator remains separate from the operator-only
generic publication runner. The latter declares private publication_* tables in
the session manifest, prepares bounded typed seeds locally, executes business
queries/operations through the production hub/agent and compares complete results.
It supports the three current engines; it does not authorize arbitrary operational
databases, consumer DDL, approval reports supplied by clients or retries after an
uncertain result. Restarted companions refuse generic fixture mutation.
SQL result sanitation preserves null cells (including multi-result envelopes),
while optional protocol fields remain omitted. A fixture-only
factory loses confirmation after actual native commit to test unknown outcome
and absence of another MCP dispatch; it does not simulate a real process crash.
Default desktop bootstrap/installer, concurrent vault writers, real crashes, permissions-minimum DBA
procedures, full type/trigger parity and remaining release gates still require
acceptance. See plug_mcp/docs/persona-v2/homologation-chain.md for reproducible
provisioning, teardown and scope. Do not start the operational desktop app.

## Direct agent/server process recovery evidence (2026-10-15)

The server opt-in test `sql_operation_dart_recovery.integration.test.ts` starts
two successive Dart test processes against an isolated loopback Socket.IO hub
and a shared private SQLite journal. The first exits abruptly after the durable
claim and a synthetic transaction step, before commit or journal completion.
The hub reports a non-retryable unknown outcome. After restart, get, duplicate
execute and cancel preserve the same unknown receipt and null affected-row count;
the transaction adapter is never reopened. Temporary processes and files are
owned and cleaned by the harness. This proves process/journal recovery, not a
native ODBC crash window or operational desktop acceptance.

Journal runtime close is terminal and idempotent. Initialization after close
returns a typed unavailable failure; closing during initialization cannot expose
a journal or retain its owner lock. A new runtime instance is required to reopen.
Validation: 82 agent journal/executor/RPC tests and both direct server/Dart
integration tests passed. Production opt-in and release gates remain unchanged.

The same harness now has an explicit real-ODBC matrix: PostgreSQL, SQL Server
and SQL Anywhere, each with process exit after a successful native write before
commit, and after a successful native commit before journal completion. Recovery
checks the physical rows through an independent ODBC connection: zero before
commit, exactly one after commit. Get, duplicate execute and cancel retain the
same unknown receipt; no transaction is reopened. Fixed test authority is used;
this does not certify Client approval, least-privilege grants, desktop bootstrap,
power loss or termination while the native commit call itself is still running.

Run the server's `vitest.sql-recovery.config.mjs` with
`RUN_DART_SQL_OPERATION_TRANSPORT=true`, `FLUTTER_BIN` and
`PLUG_SQL_OPERATION_NATIVE_MANIFEST` pointing to a freshly provisioned private
three-engine manifest; put its PostgreSQL driver and SQL Anywhere Bin64 on PATH.
The explicit config omits global application/Prisma setup and blocks dotenv;
Flutter children receive only toolchain environment and fixture selectors.
Without the native manifest the same config runs the synthetic regression.
Never use operational sources or run concurrently with another Flutter runner.
Validation on 2026-10-15: all six real-ODBC cases and the synthetic regression
passed; Dart analysis, server lint and TypeScript checks passed. The private
database fixture was removed after the run. Production gates remain blocked.

## In-flight native commit and restricted principal (2026-10-15)

The direct agent/server matrix now has nine cases: the three engines above each
run before-commit, after-commit and in-flight-commit interruption. The last case
uses a private loopback TCP proxy. After a barrier immediately before the real
ODBC commit call, the proxy observes the outgoing request and withholds incoming
server bytes. The controller confirms that the native call has not returned,
then kills only the owned agent process tree. Restarted get/execute/cancel keep
the same unknown receipt and never reopen a transaction. Physical verification
finds zero rows before commit and one after commit or withheld confirmation.
All nine cases passed. This covers a native call awaiting confirmation, not a
database-server crash, power loss or every storage-durability failure window.

Every native case now uses a fresh restricted login with SELECT/INSERT on the
exact fixture table, plus the engine's required identity metadata access
(PostgreSQL pg_control_system EXECUTE; SQL Anywhere marker SELECT). The private
DBA connection provisions and independently observes only the named fixture.
The restricted login proves the same physical identity, cannot UPDATE/DELETE,
ALTER/DROP or read/write an unrelated table, and loses insertion after REVOKE.
Post-revocation physical rows remain unchanged. Fixed test authority remains in
the direct harness; Client approval and transport authorization belong to the
separate authenticated chain acceptance.

## Isolated native desktop bootstrap (2026-10-15)

`tool/homologation/desktop_bootstrap_fixture.dart` is an explicit Windows debug
target using the real AppInitializer, dependency graph, window/tray, AppRoot,
ODBC worker, SQLite journal and production Socket.IO/RPC dispatcher. Its native
path-provider lookup points only to an exclusive temporary profile. The
production DPAPI adapter completes a secret roundtrip; configuration stays empty,
database quick_check returns ok, and SQL operations remain disabled and absent
from negotiation. First-frame rendering, rpc.discover, clean shutdown and restart
are checked; installation identity persists and boot session identity changes.

Build that target with Flutter Windows debug, copy the complete debug bundle to
`build/homologation/desktop-bootstrap`, then run the server's
`vitest.desktop-bootstrap.config.mjs` with RUN_NATIVE_DESKTOP_BOOTSTRAP=true.
The private executable uses the existing native --installation-check mode to
coexist with an installed instance. The optional setupDependencies storageContext
injects the private directory; normal entry points keep default storage resolution.
Machine auto-start repair, notifications and updater registrations are excluded
locally to avoid sharing the installed application's OS identity. Those policies,
installer bootstrap with real configured credentials, power loss and coordinated
release gates remain separate acceptance. Production installer/appcast stay blocked.

Final validation: nine real-ODBC cases, 61 bootstrap/journal regressions, the
native desktop cold/restart integration and synthetic recovery regression passed.
The ready marker is atomically published; the controller waits for agent:ready
before RPC. Native bootstrap and shutdown require no uncaught UI/zone errors.
Server lint/type checks passed. The private database fixture and temporary app
profiles were removed; the installed app remained running throughout the test.

## Qualified transactional resources

MCP compilation quotes schema and table separately for PostgreSQL, SQL Server and SQL Anywhere, including generated-output reads and reconciliation. Resource names are canonical; three/four-part references, linked servers and arbitrary scripts remain refused.

sql.operation.execute authorizes exact normalized resources, not basename matches. A qualified grant does not authorize a different schema or an unqualified target. Decisions neither read nor write the legacy authorization cache; other methods retain their prior semantics. Global-scope flags retain the existing policy behavior. Live credentials, policy and source are still rechecked at every step/commit. Existing snapshots and grants are not silently rewritten or expanded. Shared-knowledge DML adoption and full native/collation/Unicode acceptance remain pending; release remains blocked.

## SQL Anywhere 16 constraint proof

Fixed catalog queries use public SYSCONSTRAINT/SYSIDX/SYSIDXCOL/SYSPHYSIDX and
SYSFKEY metadata. Only declared PK/UNIQUE/FK on local base tables with physical
backing are enabled; a foreign key also requires the parent declared PK/UNIQUE
and its physical index. Ordinary/virtual unique indexes are excluded from the
UNIQUE-constraint result. Other server versions, proxies and incomplete evidence
remain unproven. Internal not_enforced is never authority.

FK proof also checks the current fire_triggers connection property and the
CommandLine server property. Off or -gf yields disabled; missing startup evidence
or an @ option-file reference yields unknown. Only the derived status leaves the
engine: the command line, secrets, defaults and business rows are never returned.
No VALIDATE, DDL or trial DML is used by the runtime. The existing same-connection
checks and 32-statement budget are preserved. This describes observed constraints
and settings; it does not certify the entire history of stored rows or eliminate
concurrent administrative changes.

Operator-only tool/homologation/sql_anywhere_constraints_test.dart requires an
explicit private PERSONA_SQL_FIXTURE_MANIFEST and never loads .env. Tests cover
native constraint violations only in isolated data, SELECT-only metadata access,
fire_triggers Off, missing backing and unsupported/missing evidence. The global
-gf/@ cases use fixed substituted metadata expressions, not a restarted -gf
server. Full product acceptance and version expansion remain pending.

References: https://help.sap.com/docs/SAP_SQL_Anywhere/e38b2f6217f24bdb90a3ff8ae57b1dd5/819066a26ce21014a2899cdf8e0a070a.html
and https://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.12.0.1/dbadmin/fire-triggers-option.html.

## Existing Windows installation and configured desktop (2026-10-15)

The explicitly approved real-host optional repair was validated on Windows 11
build 26300, global Plug Agente 1.8.7+1 in Program Files, with an existing configured
profile and authorized updater. A private ACL-protected local backup contains the
application, consistent SQLite snapshots, settings and encrypted vault. Never
publish that backup or use the operational profile as a business-test fixture.

The first installer run exposed an unwanted side effect: silent optional repair
inherited Authorized=1 despite /AUTOUPDATE=0, copied the worker and enrolled the
updater again. That run is rejected as acceptance evidence. WantsAutomaticUpdates
now requires the optional repair's explicit /AUTOUPDATE=1 instead of inheriting
prior authorization. Interactive selection and routine authorized service updates
retain their existing behavior. The repair validator also rejects mutating updater
commands and changed updater binaries/policy; it records failed preflight checks.

The corrected installer was compiled without changing version, solely for this
repair acceptance, and passed the approved real-host run with /REPAIR=optional,
/AUTOUPDATE=0 and /NOCLOSEAPPLICATIONS. No updater mutation commands ran; updater
binary/policy hashes, installed EXE hashes, profile-table fingerprints, encrypted
vault hash, Run/StartupApproved, plugdb command and updater authorization matched
the prepared snapshot. Core/ODBC/data probes passed. A separate non-elevated data
probe passed; the existing updater service remained Running/Automatic. This is
optional repair acceptance, not a full install/upgrade/uninstall lifecycle or a
new release bundle. Presence of an ODBC driver does not certify DB connectivity.

The native desktop fixture now also seeds one private configured profile using
the production repository and Windows DPAPI. Its server test uses the actual hub
HTTP/Socket.IO routes, registration approval, agent ownership, login and refresh.
AppRoot restores and refreshes the session itself; the controller never connects
it manually. Restart deletes the bootstrap seed and receives no credential env
variables. Configuration/installation identity persists, boot identity changes,
SQLite contains no raw access/refresh/ODBC password, and SQL operations stay off.
The fixture's SQL Server target is deliberately offline on loopback port 1; warm-up
may consume the native driver's timeout, after which Hub auto-connect succeeds.
Real three-engine SQL acceptance remains the separate ODBC matrix described above.

Validation passed: 31 installer/repair tests, four real Win32 Run/StartupApproved
adapter tests with unique temporary value names, 29 bootstrap/session/shell
regressions, and both native desktop cold/restart integrations (empty and configured).
Flutter analysis, server source/test lint and TypeScript test type checking passed.
Temporary desktop profiles and HKCU test entries were removed; protected real-host
backups are retained locally. The fixture was rebuilt and launched in fresh native
processes; hot reload could not attach because neither discovered DTD had a live app.

Remaining acceptance includes full clean install/upgrade/uninstall on supported
Windows targets, actual logon/protocol activation and notification registrations,
updater migration/application/recovery and signing/distribution gates. Preservation
of existing registry values does not certify every Windows shell activation flow.
Production installer/appcast remain blocked; no release gate was promoted.

## Managed pagination output aliases

The pagination wrapper orders by projected output names, not inner table aliases.
Qualified ORDER BY terms require an exact simple column projection; explicit
aliases are preserved for both outer ORDER BY and cursor row lookup. Missing,
duplicate or unprovable projected names fail validation. Qualified sorting with
complex projections, wildcard or CTE is not supported by this narrow mapping;
use a proved simple output alias or a compatible query shape. The MCP/hub do not
rewrite business SQL. Existing query fingerprints still identify the original
query; incompatible old cursor terms are rejected, never silently reused.

The 2026-10-15 MCP limits round passed 41/41 persistent chain scenarios across
PostgreSQL, SQL Server and SQL Anywhere after fixing out-of-scope qualified sorting.
Agent pagination/validation regressions passed 74/74; analysis of changed files
passed. This is partial evidence, not installer or production acceptance. Reduced
budgets from MCP do not replace the agent's policy and transaction guards.

## Qualified installer/service lifecycle — 2026-10-15

The namespaced Windows 11 manual lifecycle passed real installation, repair,
missing-client recovery, migration from a historical contract-1 supervisor to
contract 2, removal and reinstalls while preserving the operational installation.
Non-elevated authenticated service IPC/DPAPI/ACL refusals and twenty signed
prepare/cancel cycles passed. Native temporary notification registration/show/cancel
also passed cold/restart through the desktop/hub harness. Version stays 1.8.7.
The discovered buffered-reply/partial-read defect was fixed; no business RPC,
SQL operations or MCP implementation changed. Authoritative scope, artifacts and
remaining apply/rollback, shell-activation and OS matrix blockers are in
[the updater plan](../implemente/plano_auto_update_evolution.md#qualified-windows-lifecycle-and-ipc-delivery-2026-10-15).
Production gates remain blocked. Prepare/cancel cycles are not automatic-apply acceptance.

## Private publication matrix

The operator companion accepts typed composite foreign keys and insertAudit
copy triggers only inside the owned publication_* fixture namespace. Targets
and columns are validated before connecting; setup SQL is fixed by engine, never
provided by a consumer. Tables are dropped in reverse dependency order and
rebuilt with their constraints/triggers after confirmed terminal cases.
MCP runner compares exact integer/decimal representations and all seeded tables.
Expected native errors require confirmed rollback, SQL_OPERATION_NATIVE_FAILED
and unchanged seeds; they do not identify a constraint from a native diagnostic.
Trigger side effects are checked separately from directly affected rows.
This is development-only; production release remains blocked. See the MCP
persona-v2/homologation-chain.md contract for the case and manifest formats.

## Private CHECK/cascade/update/delete publication cases

Private fixture declarations now accept integer_range CHECKs with textual int64
bounds, explicit onUpdate/onDelete cascade actions, and updateAudit/deleteAudit
copy triggers. UPDATE copies NEW and DELETE copies OLD into distinct destinations;
trigger chains and consumer SQL bodies remain rejected. CHECK preserves native
NULL/UNKNOWN semantics and does not replace NOT NULL. Seeds are inserted normally;
UPDATE/DELETE triggers are not fired during provisioning. Composite cascade cases
preserve a second tenant and verify rollback after a descendant CHECK or later
step fails. Direct row counts exclude cascaded changes and trigger rows, which the
MCP runner checks separately. This adds no public RPC capability or production DDL.


## Binary column metadata in verified SELECTs

Rich column metadata preserves the odbc_fast protocol discriminant in odbc_type
with type_system=odbc_fast. Discriminant 7 means raw binary in that namespace;
it is not native ODBC SQL_REAL (7). Do not infer binary from untagged positive
codes or base64-looking strings. Existing names/codes remain unchanged and
metadata schemas remain additive. Verified expectedSource responses explicitly
report truncated=false only when no cut occurred. A single binary projection
can order by its physical key without managed pagination; an explicit response
limit and completeness flag must prove the one-record result. The private chain
fixture seeds binary_fixture only after checking its disposable database name,
grants read only, and never recreates its rows after vault recovery. Production
release, public HTTPS and real ChatGPT acceptance remain blocked.

## Windows vault concurrency correction (2026-10-20)

The production adapters still use flutter_secure_storage. The local Windows
backend override preserves the DPAPI format and keys while serializing complete
map operations across processes, replacing only fully flushed ciphertext, and
refusing unreadable content without deletion. Provenance and limits are in
third_party/flutter_secure_storage_windows/README.md. Never edit Pub cache.

The MCP probe-persona-agent-vault.ps1 runner reproduced missing keys before the
fix. Afterward, two processes preserved 200 synthetic keys; contention failed
within its deadline without changing ciphertext, terminating the private lock
holder released the lock, and corrupt input was preserved on refused read/write.
No operational vault was opened. This does not certify power loss, atomic groups
of credentials, old/new concurrent binaries or the installed upgrade lifecycle.
Keep deploy and installer/appcast blocked; stop all vault users before upgrade.


## Bounded manual training companion

The MCP manual-training controller may supply manualTraining with format
persona-manual-training-v1 and an absolute UTC expiresAt, at most two hours ahead.
The private companion preserves that fixed deadline and exits cleanly on deadline
or its agents-stop file. Without the option the twelve-minute automated watchdog
and fourteen-minute test timeout remain unchanged. SQL budgets, journal semantics,
authentication and approval lifetimes are not extended. This is a disposable
Flutter companion with native ODBC/vault, not proof of the installed desktop app.
