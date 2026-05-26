# Communication

Documentos do contrato Socket.IO / Plug JSON-RPC entre o agente e o hub.

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

## Convencao de manutencao

- Itens concluidos vao para o **roadmap** (changelog historico) e o
  **standard** (estado atual). Nunca duplicar entre `roadmap.md` e
  `backlog.md`.
- O `standard.md` e a fonte de verdade do contrato implementado; nao adicionar
  ali itens ainda nao entregues.
