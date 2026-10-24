# Plug Agente project overview

## Purpose and topology

Plug Agente is a Windows desktop application that executes local SQL through
ODBC and approved system actions for a central hub (`plug_server`). It initiates
an outbound Socket.IO connection; consumers reach the hub rather than a public
agent listener.

```text
Consumer -> plug_server (HTTP / Socket.IO) -> plug_agente -> ODBC / Windows
```

The hub authenticates and routes requests. The agent maintains its connection,
executes local work and returns results through the negotiated protocol.
The current database scope is PostgreSQL, SQL Server and SQL Anywhere.

## Capabilities and contracts

| Area | Responsibility | Detailed contract |
| --- | --- | --- |
| Transport | Registration, capabilities, readiness, heartbeat, binary PayloadFrame, streaming and delivery control | [Socket standard](communication/socket_communication_standard.md), [client guide](communication/socketio_client_binary_transport.md) |
| SQL | Bounded queue, ODBC execution, batches, bulk insert and cancellation | [ODBC runtime](runtime/odbc_pool_and_transactions.md) |
| Source verification | Negotiated physical identity and structural checks | [Source discovery](communication/source_discovery.md) |
| Durable SQL operations | Journal, single-source transactions, cancellation and uncertain-outcome reconciliation | [SQL operations](communication/sql_operations.md) |
| Actions | Local scheduling, approved remote execution, audit and retention | [Action RPC](communication/socket_agent_actions.md), [implementation plan](implemente/plano_acoes_agendadas_execucoes.md) |
| Updates | Signed feed/manifest verification and Windows service integration; automatic application remains blocked | [Update guide](install/auto_update_setup.md), [acceptance plan](implemente/plano_auto_update_evolution.md) |

The method catalog lives in [OpenRPC](communication/openrpc.json), with
[JSON schemas](communication/schemas/) for request/result validation. Method
presence does not bypass feature flags, authorization or capability negotiation.

## Layers

```text
lib/
|- domain/         # entities, ports, failures and protocol
|- application/    # use cases, SQL queue, scheduler and mappings
|- infrastructure/ # ODBC, transport, persistence and codecs
|- presentation/   # pages, providers, controllers and widgets
|- core/           # configuration, DI, routes, theme and runtime utilities
|- bootstrap/      # startup, dependency registration and shutdown
|- l10n/           # localization resources
`- shared/         # shared UI components
```

Dependency rules belong to [clean_architecture.mdc](../.cursor/rules/clean_architecture.mdc);
repository decisions belong to [project_specifics.mdc](../.cursor/rules/project_specifics.mdc).
[Layer boundary tests](../test/architecture/layer_boundaries_test.dart) enforce
these boundaries. SQL RPC handlers live in `lib/application/rpc/`, with
`sql_rpc_method_handler_operations.dart` composing execution, batch, bulk insert
and cancellation handlers.

## Local persistence

- [AgentConfigDriftDatabase](../lib/infrastructure/repositories/agent_config_drift_database.dart)
  owns configuration, execution history and audit storage. Its current schema is
  version 30; migration removes the plaintext ODBC password column after moving
  remaining credentials into secure storage.
- [SqlOperationJournalDatabase](../lib/infrastructure/stores/sql_operation_journal_database.dart)
  has an independent schema and durable operation journal. Its lifecycle and
  recovery rules are documented in [SQL operations](communication/sql_operations.md).
- `flutter_secure_storage` stores ODBC credentials, hub authentication, token
  secrets, signing keys and action secrets through dedicated stores. The Windows
  backend coordinates processes; old binaries require a coordinated upgrade.
- `shared_preferences` stores lightweight preferences.
- Local backup export omits secure-storage secrets by default. Explicit opt-in
  includes eligible secrets; the [backup manifest](backup/local_backup_manifest.schema.json)
  records the selected scope.

## Desktop and security

The desktop uses `window_manager` and `tray_manager`, with a machine-wide
single-instance mutex. Windows startup behavior belongs to
[requirements](install/requirements.md); installation and data-retention behavior
belong to the [installation guide](install/installation_guide.md).

Hub authentication, payload signing and token policy checks are described in the
[communication standard](communication/socket_communication_standard.md).
Action-specific approval, redaction and execution controls are indexed in
[action security](implemente/acoes/seguranca_acoes.md).

## Development and release status

The repository contains implemented features under ongoing homologation.
The [persona-v2 manifest](../contracts/persona-v2-release.json) remains
`ready: false`. Production installer/appcast publication and Windows automatic
application are still blocked. Isolated fixtures and historical engine runs do
not certify the full installed lifecycle or authorize production publication.

Use the [documentation index](readme.md) for operating guides and the
[implementation index](implemente/readme.md) for current acceptance work.
