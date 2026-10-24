# Plug Agente documentation

Start with the [project overview](project_overview.md). Use the topic indexes
below for detailed procedures and contracts.

## Find the right document

| Task | Entry point |
| --- | --- |
| Understand the agent, layers and local storage | [Project overview](project_overview.md) |
| Integrate Socket.IO / JSON-RPC | [Communication](communication/readme.md) |
| Verify database identity and structural dependencies | [Source discovery](communication/source_discovery.md) |
| Understand durable SQL operations and reconciliation | [SQL operations](communication/sql_operations.md) |
| Configure an ODBC connection | [Database guides](database/readme.md) |
| Tune ODBC or investigate queue/pool behavior | [Architecture and operations](architecture/readme.md) |
| Check runtime defaults and transaction behavior | [ODBC runtime](runtime/odbc_pool_and_transactions.md) |
| Install or uninstall on Windows | [Installation](install/readme.md) |
| Build, sign or prepare a release | [Release guide](install/release_guide.md) |
| Configure and diagnose updates | [Auto-update](install/auto_update_setup.md) |
| Review update security assumptions | [Auto-update threat model](security/auto_update_threat_model.md) |
| Run local, integration or live tests | [Testing](testing/readme.md) |
| Check implementation status and remaining acceptance | [Implementation plans](implemente/readme.md) |
| Validate a local backup manifest | [Backup schema](backup/local_backup_manifest.schema.json) |

## Current release boundary

Production installer/appcast publication remains blocked by the
[persona-v2 release manifest](../contracts/persona-v2-release.json).
Windows automatic update application also remains disabled; its acceptance
criteria and evidence belong to the [updater plan](implemente/plano_auto_update_evolution.md).
Local or isolated test results do not remove these gates.

The current database scope is PostgreSQL, SQL Server and SQL Anywhere.
Historical Firebird evidence does not establish current support.

## Documentation ownership

- [Repository rules](../.cursor/rules/rules_index.mdc) own development conventions.
- [OpenRPC](communication/openrpc.json) and [JSON schemas](communication/schemas/)
  own the machine-readable wire contract. The communication guides explain it.
- Topic guides own operating procedures; indexes link to them instead of copying them.
- Implementation plans own feature status and acceptance. The communication
  [roadmap](communication/socket_communication_roadmap.md) records deliveries;
  the [backlog](communication/socket_communication_backlog.md) tracks remaining work.
- Dated reports and changelogs are historical evidence, not current acceptance.
  Preserve their scope and dates when referencing them.

Use relative links and section anchors. Keep existing document paths stable
when consolidating content so external references continue to work.
