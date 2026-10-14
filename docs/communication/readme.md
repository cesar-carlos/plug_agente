# Communication

Documentos do contrato Socket.IO / Plug JSON-RPC entre o agente e o hub.

Reviewed on **2026-10-03** against repository HEAD `abbbf9a4` and the local
runtime sources. Protocol and OpenRPC remain **2.11.2**. The review covers
event framing exceptions, stream arrival order and columnar chunks, admission
limits/reasons, SQL source-read authorization, health schemas, and client
examples. Live hub deployment settings and pending E2E rollout items require
separate validation; see the backlog.

| Arquivo                                                                    | Quando consultar                                                                                                                                         |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [socket_communication_standard.md](socket_communication_standard.md)       | Fonte de verdade do contrato implementado: eventos, handshake, heartbeat, RPC, streaming, errors, batch, signing, schemas. Tem TOC de navegacao no topo. |
| [socket_agent_actions.md](socket_agent_actions.md)                         | Detalhe dos metodos `agent.action.*` (`run`, `validateRun`, `getExecution`, `cancel`, policy metadata, auditoria remota).                                |
| [socketio_client_binary_transport.md](socketio_client_binary_transport.md) | Guia obrigatorio para quem implementa cliente publicando/consumindo eventos com `PayloadFrame`.                                                          |
| [socket_communication_roadmap.md](socket_communication_roadmap.md)         | Changelog historico do que ja foi entregue por versao do protocolo + criterios de rollout.                                                               |
| [socket_communication_backlog.md](socket_communication_backlog.md)         | Backlog ativo: itens ainda pendentes de evolucao.                                                                                                        |
| [openrpc.json](openrpc.json)                                               | Documento OpenRPC publicado pelo `rpc.discover`.                                                                                                         |
| [schemas/](schemas/)                                                       | Schemas JSON dos params e results de cada metodo + envelopes RPC + frames de transporte.                                                                 |

## Validacao

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

## Inspeção estrutural sourceSchema v1

Extensão aditiva, em desenvolvimento e sem liberação de deploy. `sql.describeSchema`
exige `sourceSchema`/`sourceIdentity` v1, ID correlacionável, token vigente,
ClientAgentAccess upstream e banco obrigatório da policy. Inspeciona somente recursos
explicitamente autorizados; recebe até 16 recursos únicos e pagina até quatro.
Schemas são explícitos; Firebird usa schema nulo. SQL, DSN ou conexão do consumidor
não entram nesse contrato. As consultas aos catálogos são fixas e os nomes são valores
parametrizados. O agente usa a mesma conexão para identidade antes/depois e metadados.

Retorna tipos/nulabilidade, PKs, índices únicos e FKs com pares ordenados e somente
alvos no escopo autorizado. Defaults, comentários e linhas de negócio não são enviados.
`coverage`/`limitations` distinguem informação incompleta; visibilidade limitada
não prova inexistência. Estados são enabled/disabled/unvalidated/unknown por recurso.
PostgreSQL verifica índices/validação e triggers de FK; SQL Server índices e confiança
das FKs; Firebird índices associados. Índices parciais ou por expressão não provam
unicidade global. SQL Anywhere mantém enforcement desconhecido: o indicador interno
not_enforced não habilita dependências. `metadataPage` é separado da paginação SQL;
nulos obrigatórios são preservados, inclusive schema Firebird.

`sql.execute.expectedStructure` exige as mesmas capabilities e `expectedSource`.
Contém recursos, colunas e constraints utilizadas; constraints exigem também
sourceConstraints v1. Destinos de FK devem pertencer ao escopo autorizado. A policy
autoriza os recursos; a mesma conexão confere colunas e chaves/ordem/status antes e
depois do SELECT. Divergência descarta linhas com SOURCE_STRUCTURE_MISMATCH, sem
reconectar/repetir. DML, prova de enforcement SQL Anywhere e matriz completa de
mínimos privilégios/views continuam pendentes. Prova não aprova significado de negócio.

Referências técnicas dos catálogos: [PostgreSQL pg_constraint](https://www.postgresql.org/docs/15/catalog-pg-constraint.html),
[SQL Server sys.columns](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-columns-transact-sql?view=sql-server-ver16),
[SQL Anywhere SYSIDXCOL](https://help.sap.com/docs/SAP_SQL_Anywhere/93079d4ba8e44920ae63ffb4def91f5b/3be8e1416c5f1014aa0185d6ff33803a.html)
e [Firebird RDB$RELATION_FIELDS](https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref25/fblangref-appx04-relfields.html).
SQL e schemas efetivos estão no runtime e nos JSON/OpenRPC empacotados; referências
não substituem execução dos testes reais de cada versão/driver.
