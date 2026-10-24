# Hub and three-engine homologation — 2026-10-24

## Scope and candidate

This is local development evidence for the communication changes through agent
commit `cfac768e`. It is not a coordinated release approval. The agent, hub and
MCP working trees had unrelated changes in progress; this run does not certify a
clean or frozen release candidate. No release gate, production opt-in, operational
configuration or contract pin was changed.

| Component | Observed version/revision |
| --- | --- |
| Agent | `cfac768e` plus pre-existing local changes |
| Hub checkout | `421c4fc6c24ec48f147a11d6d1e7f2ddf9435ad4` plus local changes |
| MCP checkout | `136b5bfc8f7104b753bbd3703c9ffda196fdd51f` plus local changes |
| Node / Vitest | 24.21.0 / 5.0.5 |
| Native ODBC package | `odbc_fast` 5.0.1, cached release verified by `prepare_package_native.py` |
| PostgreSQL | 17.11 |
| SQL Server | 2022, 16.0.4236.2; ODBC Driver 18 |
| SQL Anywhere | 16.0.0.2043, 64-bit |
| Docker engine | 29.7.2 |

Native DLL SHA-256:
`2faf9f21fd09b6a206ce02b6ecebbc6182e8202909943a97b2f736535f08ee9a`.
The PostgreSQL driver was taken from the existing private MCP driver cache;
no global driver installation was performed. The DLL hash identifies the asset
explicitly selected for direct Flutter native runs. The hub recovery harness
filters child environment variables and does not forward `ODBC_FAST_NATIVE_LIBRARY`;
its passing results are not a per-process attestation of that DLL hash.

## Results

| Check | Result | Meaning |
| --- | --- | --- |
| E2E environment inventory | Completed | Hub flags and credentials present; no dedicated persona manifests were supplied. Configured DSNs were not used. |
| Live hub readiness | Blocked, exit 1 | `E2E_HUB_TOKEN` expired. No remote Socket.IO authentication attempted. |
| MCP chain contract preflight | Blocked, exit 1 | Hub HEAD differs from the reviewed MCP base commit. No pin/snapshot bypass or full chain startup. |
| Native three-engine operation matrix | Passed, 57 tests | 19 cases per engine; real transactions, identity, structure, row counts, scalar bindings, rollback, revocation, duplicate suppression and journal recovery. |
| Restricted identity principals | Passed, 3 tests | One per engine: metadata proof, denied business access, explicit SELECT grant and revocation. |
| SQL Anywhere constraint matrix | Passed, 6 tests | Native PK/UNIQUE/FK behavior, trigger enforcement, conservative unknown states and SELECT-only proof. |
| Isolated hub/agent recovery | Passed, 9 tests | Three engines × before/after/in-flight commit; local Socket.IO and real native transactions. |
| SQL Anywhere identity lifecycle | Passed, 10 tests in five phases | Missing marker (1), enrollment (6), restart (1), restore (1), replacement/re-enrollment (1). |

Total: **85 native/integration test cases passed**, with no skips in those suites.
The separate documentation/contract check also passed 85 tests; these are not
additional native homologation cases. All 300 local Markdown links resolved.

No skip is counted as a pass. The native operation matrix uses synthetic
authority, not real Client approval. The recovery harness uses production bridge,
transport, executor and journal components with fixed test authority and a local
Socket.IO server; it does not certify the deployed hub, full REST/Prisma approval,
Redis distribution, OAuth, publication or MCP composition.

The first recovery collection attempt failed before running tests because
`.prisma/client/default` was missing. Generating Prisma Client 7.10.1 in the hub's
ignored `node_modules` succeeded. No migrations or operational database access
were required. The recovery suite was then restarted and all nine cases passed (112.72 seconds).
Before-commit recovery observed zero rows; after-commit and in-flight-confirmation
loss observed one row. Every case required zero replayed transactions and stable
unknown receipts across repeated requests.

## Persistent blockers and next steps

1. Renew the dedicated live hub token through the approved test login flow, then
   rerun `validate_live_hub_agent_actions_env.dart`, Socket.IO smoke and signed
   `agent:register` / `agent:capabilities` checks. No installed vault was read and
   no token or signing key was exported or changed during this review.
2. Review the MCP hub pin and snapshot against the intended candidate. At the
   preflight, MCP expected `0dc94d6990167f65e093b1fb68a8150630e2057c`, while hub
   HEAD was `421c4fc6c24ec48f147a11d6d1e7f2ddf9435ad4`. The bundled and current hub
   REST contract bytes had the same SHA-256
   `a8e8bc82a9b6d995c8637bf47bc35e17d44c5b21aba60889be25654ac60f4e60`;
   matching bytes do not satisfy the runner's reviewed-commit requirement.
3. After that review, use a new fixture for the default Prisma-backed full MCP →
   hub → agent chain, including approval/revocation, publication, federation,
   composed restart and persistence. Do not reuse an uncertain operation or
   translate response ACK retry into execution replay.
4. Complete the remaining coordinated acceptance criteria in
   [persona-v2-release.json](../../contracts/persona-v2-release.json). It remains
   `ready: false` with no completed gates. The current native tests cover narrow
   behaviors and do not complete the whole type/trigger/privilege matrix,
   installation acceptance or production rollout.

## Reproduction and isolation

The existing `new-persona-chain-fixture.ps1 -PrivateAccess` provisioned a fresh
`se7e_persona_<12 hex>_test` root: new loopback PostgreSQL, SQL Server and Redis
containers, a dedicated SQL Anywhere process, a temporary PostgreSQL user DSN and
synthetic credentials. Its DBA explicitly provisioned the SQL Anywhere identity
marker. No existing source, DSN or business database was selected as a substitute.

Run sequentially, with `ODBC_FAST_NATIVE_LIBRARY` set to the verified DLL and the
private PostgreSQL driver plus SQL Anywhere `Bin64` on the child process PATH:

```powershell
# From plug_mcp, using the new private manifest:
./scripts/run-four-engine-homologation.ps1 -Manifest <private-manifest> -Flutter <flutter.bat> -DriverDirectories <private-pgdriver>,<sql-anywhere-bin>

# From plug_agente, PERSONA_SQL_FIXTURE_MANIFEST points to that manifest:
flutter test --no-pub --concurrency=1 tool/homologation/source_identity_permissions_test.dart tool/homologation/sql_anywhere_constraints_test.dart --reporter expanded

# From plug_server, with RUN_DART_SQL_OPERATION_TRANSPORT=true,
# PLUG_SQL_OPERATION_NATIVE_MANIFEST, PLUG_AGENTE_ROOT and FLUTTER_BIN explicit:
node node_modules/vitest/vitest.mjs run --config vitest.sql-recovery.config.mjs --reporter verbose

# From plug_mcp, a different new direct child of the system temporary directory:
./scripts/run-sql-anywhere-identity-homologation.ps1 -FixtureRoot <new-private-root> -Flutter <flutter.bat>
```

The legacy `four-engine` filenames now execute exactly PostgreSQL, SQL Server and
SQL Anywhere. Firebird is not included. Runners sharing the native DLL were not
executed concurrently.

Local command logs are under `build/homologation_*.log` and are not committed:
preflight inventory/readiness, training-base check, fixture setup, native matrix,
identity/constraints, Prisma generation, recovery attempts, identity lifecycle
and fixture cleanup. Never publish raw fixture manifests or logs without checking for credentials.

## Cleanup

Cleanup completed after all runs. The guarded MCP cleanup removed only the
new three-engine fixture `se7e_persona_1b36fd7236ca_test`, its labeled containers
and anonymous volumes, dedicated SQL Anywhere process and temporary DSN.
The identity-lifecycle runner stopped its own SQL Anywhere process; its exact
temporary root `se7e_persona_fb4cffdbcb29_test` was then removed after checking
its resolved parent and confirming no fixture process remained. Both roots,
the temporary DSN and all containers carrying the owned fixture label were
confirmed absent. Other fixtures and operational installations were preserved.
