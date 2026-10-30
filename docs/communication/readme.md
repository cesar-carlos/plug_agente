# Communication

Documentos do contrato Socket.IO / Plug JSON-RPC entre o agente e o hub.

Protocol version and available methods are recorded in [OpenRPC](openrpc.json).
Development extensions require explicit capability negotiation and authorization;
their presence does not imply production release. Current scope is PostgreSQL,
SQL Server and SQL Anywhere. Historical Firebird evidence is not current support.

| Arquivo                                                                    | Quando consultar                                                                                                                                         |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [socket_communication_standard.md](socket_communication_standard.md)       | Fonte de verdade do contrato implementado: eventos, handshake, heartbeat, RPC, streaming, errors, batch, signing, schemas. Tem TOC de navegacao no topo. |
| [socket_agent_actions.md](socket_agent_actions.md)                         | Detalhe dos metodos `agent.action.*` (`run`, `validateRun`, `getExecution`, `cancel`, policy metadata, auditoria remota).                                |
| [socketio_client_binary_transport.md](socketio_client_binary_transport.md) | Guia obrigatorio para quem implementa cliente publicando/consumindo eventos com `PayloadFrame`.                                                          |
| [socket_communication_roadmap.md](socket_communication_roadmap.md)         | Changelog historico do que ja foi entregue por versao do protocolo + criterios de rollout.                                                               |
| [socket_communication_backlog.md](socket_communication_backlog.md)         | Backlog ativo: itens ainda pendentes de evolucao.                                                                                                        |
| [openrpc.json](openrpc.json)                                               | Documento OpenRPC publicado pelo `rpc.discover`.                                                                                                         |
| [source_discovery.md](source_discovery.md) | Physical identity, structural inspection and verified SELECT requirements. |
| [sql_operations.md](sql_operations.md) | Durable operation journal, transactions, reconciliation and scoped acceptance evidence. |
| [action_io.md](action_io.md) | Faithful remote process I/O: authorization, byte semantics, journal, limits, recovery and acceptance evidence. |
| [schemas/](schemas/)                                                       | Schemas JSON dos params e results de cada metodo + envelopes RPC + frames de transporte.                                                                 |

## Documentation update — 2026-10-30

The main catalog includes faithful I/O, and the actions guide distinguishes its
guarantees from the legacy flow. Retry guidance requires proof of no dispatch or
reconciliation, not just a transient classification. The backlog separates process
I/O acceptance from pending SQL and shared transport acceptance.

In the hub, `tests/contract/agent_communication_docs.contract.test.ts` compares all
published OpenRPC methods with the standard's implemented scope.
`remote_action_io_documentation.contract.test.ts` validates capability examples
and request/response pairs against runtime validators. Run these tests with both
repositories available; skipping because the agent is absent is not acceptance.

## Review baseline

The [standard](socket_communication_standard.md) was reviewed on 2026-10-24
against local handlers, negotiation, OpenRPC and schemas. Version remains 2.11.2.
Known implementation/schema discrepancies and acceptance limits are in the
[backlog](socket_communication_backlog.md#contract-review-findings-2026-10-24).

## Validacao

- Local extension contracts and negotiation: `flutter test test/application/rpc/sql_operation_contract_test.dart test/application/rpc/source_discovery_test.dart test/infrastructure/validation/sql_operation_schema_test.dart test/infrastructure/external_services/transport/sql_operation_capability_test.dart`.
- Response schema/error handling: `flutter test test/infrastructure/external_services/transport/rpc_response_preparer_test.dart test/infrastructure/external_services/transport/rpc_response_delivery_coordinator_test.dart`.
- Source metadata with deterministic doubles: `flutter test test/infrastructure/external_services/odbc_source_schema_test.dart`. Real-driver acceptance remains separate.
- Alteracoes em `openrpc.json`: `flutter test test/docs/openrpc_contract_test.dart`.
- Fixtures de fio (envelope + params + result + error) versus schemas:
  `flutter test test/docs/communication/contract_fixtures_test.dart`.
- Fixtures vivem em `test/fixtures/rpc/`.
- Runtime health snapshots versus the published schema:
  `flutter test test/application/services/agent_get_health_result_schema_test.dart`.
- Hub inbound fixture catalog with none/GZIP/HMAC:
  `flutter test test/infrastructure/external_services/transport/hub_inbound_catalog_codec_test.dart`.
  Requires `PLUG_SERVER_FIXTURE_DIR` or the sibling `plug_server` fixture
  directory. Set `REQUIRE_PLUG_SERVER_CONTRACT=true` in mandatory cross-project
  gates: a missing catalog fails rather than skipping. The dedicated CI job
  checks out both repositories and records their exact revisions.

- Production typed columnar fixture:
  `flutter test test/docs/communication/columnar_codec_fixture_test.dart`.
  The hub checks the shared JSON against agent schemas and equivalent row maps.
- Lifecycle regressions use controlled clocks and send gates for workers,
  emitter expiry/identity, queue admission, heartbeat preparation and ordered
  control decode. Their aggregate diagnostics must drain to zero.
- Nine repeated codec profiles:
  `flutter test test/infrastructure/codecs/transport_repeated_benchmark_test.dart`.
  Set `AGENT_TRANSPORT_BENCH_OUTPUT` to keep base and candidate reports separate.
  This measures codecs; hub transport and real ODBC require separate runs.
  Compare identical reports with `python tool/benchmarks/compare_transport_repetitions.py
--base BASE.json --candidate CANDIDATE.json --output COMPARISON.json`.
  Scenario/configuration mismatches fail before applying p95 (+5%) and throughput
  (85% minimum) gates. RSS does not substitute for a Dart heap measurement;
  the report explicitly records the pending heap gate.

## Convencao de manutencao

- Itens concluidos vao para o **roadmap** (changelog historico) e o
  **standard** (estado atual). Nunca duplicar entre `roadmap.md` e
  `backlog.md`.
- O `standard.md` e a fonte de verdade do contrato implementado; nao adicionar
  ali itens ainda nao entregues / propostas (ficam no backlog ou plano).
- `openrpc.json` / `rpc.discover` lista **somente** metodos com wire ativo no
  runtime; propostas (ex. auto-update diagnostics) ficam no backlog + schema,
  fora do discover ate o hub consumir.
- Detalhe de cliente `PayloadFrame`:
  [`socketio_client_binary_transport.md`](socketio_client_binary_transport.md)
  — o standard so resume e aponta.
- Metodos `agent.action.*`: detalhe em
  [`socket_agent_actions.md`](socket_agent_actions.md).

<a id="inspeção-estrutural-sourceschema-v1"></a>

Structural inspection and its historical fixtures now live in
[source discovery](source_discovery.md#structural-inspection-sourceschema-v1).
