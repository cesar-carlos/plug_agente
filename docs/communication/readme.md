# Communication

Documentos do contrato Socket.IO / Plug JSON-RPC entre o agente e o hub.

Reviewed on **2026-10-03** against repository HEAD `abbbf9a4` and the local
runtime sources. Protocol and OpenRPC remain **2.11.2**. The review covers
event framing exceptions, stream arrival order and columnar chunks, admission
limits/reasons, SQL source-read authorization, health schemas, and client
examples. Live hub deployment settings and pending E2E rollout items require
separate validation; see the backlog.

| Arquivo | Quando consultar |
| --- | --- |
| [socket_communication_standard.md](socket_communication_standard.md) | Fonte de verdade do contrato implementado: eventos, handshake, heartbeat, RPC, streaming, errors, batch, signing, schemas. Tem TOC de navegacao no topo. |
| [socket_agent_actions.md](socket_agent_actions.md) | Detalhe dos metodos `agent.action.*` (`run`, `validateRun`, `getExecution`, `cancel`, policy metadata, auditoria remota). |
| [socketio_client_binary_transport.md](socketio_client_binary_transport.md) | Guia obrigatorio para quem implementa cliente publicando/consumindo eventos com `PayloadFrame`. |
| [socket_communication_roadmap.md](socket_communication_roadmap.md) | Changelog historico do que ja foi entregue por versao do protocolo + criterios de rollout. |
| [socket_communication_backlog.md](socket_communication_backlog.md) | Backlog ativo: itens ainda pendentes de evolucao. |
| [openrpc.json](openrpc.json) | Documento OpenRPC publicado pelo `rpc.discover`. |
| [schemas/](schemas/) | Schemas JSON dos params e results de cada metodo + envelopes RPC + frames de transporte. |

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
  directory; the suite skips when the catalog is unavailable.

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
