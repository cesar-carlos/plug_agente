# SQL operations â€” journal and transaction integration

The agent now registers `sql.operation.execute`, `sql.operation.get` and
`sql.operation.cancel` in the dispatcher. Production installer/appcast publishing
remains blocked by contracts/persona-v2-release.json. The hub forwards only after
sqlOperations version 1 negotiation. Legacy sql.executeBatch is not a substitute.

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
The fixed-table operation
case evaluator is not the general four-engine product runner. A fixture-only
factory loses confirmation after actual native commit to test unknown outcome
and absence of another MCP dispatch; it does not simulate a real process crash.
Default desktop bootstrap/installer, concurrent vault writers, real crashes, permissions-minimum DBA
procedures, full type/trigger parity and remaining release gates still require
acceptance. See plug_mcp/docs/persona-v2/homologation-chain.md for reproducible
provisioning, teardown and scope. Do not start the operational desktop app.
