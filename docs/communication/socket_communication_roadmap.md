# Socket Communication Roadmap (Delivered History)

## Objetivo

Este arquivo concentra o registro historico do que ja foi entregue no protocolo
Socket.IO / Plug JSON-RPC, alem dos criterios de rollout aplicaveis a novos
itens.

- Estado implementado atual:
  `docs/communication/socket_communication_standard.md`
- Itens pendentes (backlog ativo):
  `docs/communication/socket_communication_backlog.md`

## Itens concluidos

| Item                                                              | Concluido em |
| ----------------------------------------------------------------- | ------------ |
| Extensoes de `agent.getHealth` (secure_storage, global_storage, streaming path/worker_hold, sql_queue por tipo de worker e timeouts_after_worker_started, direct_connections.by_operation_class, prepared/timeouts/diagnostics, sql_execution_by_mode, cancelamento cooperativo); `sql.cancel` com client_token e ownership; schemas alinhados | pos-v2.11.2 |
| Plug JSON-RPC `agent.action.*` remoto (incl. `validateRun` + `skipped`), OpenRPC `2.11.2`, fixtures `test/fixtures/rpc/` | v2.11.2 |
| `api_version` + `meta` response enrichment; recommended request metadata, accepted without it for compatibility | v2.1 |
| Semantica formal de notification JSON-RPC                         | v2.1         |
| Regras formais de batch (ordem, IDs, atomicidade)                 | v2.1         |
| Politica de versao e deprecacao                                   | v2.1         |
| Schema de params para sql.execute/batch/cancel                    | v2.1         |
| Schemas de streaming (chunk/complete/pull)                        | v2.1         |
| Limites negociados documentados (defaults)                        | v2.1         |
| Assinatura de payload especificada                                | v2.1         |
| Negociacao de limites no handshake (TransportLimits)              | v2.2         |
| Assinatura de payload implementada (hmac-sha256, PayloadSigner)   | v2.2         |
| Feature flags estaveis promovidas para mandatory                  | v2.2         |
| Transporte binario em `PayloadFrame` para eventos de aplicacao    | v2.4         |
| Compressao GZIP na borda de transporte com fallback por threshold | v2.4         |
| Rotacao manual de chaves por `key_id` e diagnostico de assinatura | pos-v2.8     |
| HMAC-SHA256 isolate offload from 64 KiB (`PayloadSigner.signFrameAsync`); current runtime uses reusable `TransportWorkPool` workers | pos-v2.11 |
| Reusable JSON/GZIP/HMAC worker pool, dedicated chunk thresholds, columnar wire chunks, and bounded decompression | pos-v2.11.2 |
| Stream emitter default 16, dynamic handler admission, distinct rate/concurrency/output reasons, and SQL response ACK bypass | pos-v2.11.2 |
| SQL authorization includes source reads in INSERT SELECT, DELETE JOIN, MERGE USING and view definitions | pos-v2.11.2 |
| `trace_id` em `agent:heartbeat` para correlacao de rastreamento distribuido | pos-v2.11 |
| `rpc:stream.pull` registrado para qualquer flag de streaming ativa (nao so backpressure) | pos-v2.11 |
| Codigos terminais vs recuperaveis de `agent:register_error` documentados e implementados | pos-v2.11 |
| Wire `agent:register_error` alinhado ao hub (`reason` canonico, `authentication_failed` / `session_active`; so `transient_failure`+`rate_limited` recuperaveis) + eventos `connection:ready` / `agent:session.superseded` / profile socket documentados | pos-v2.11.2 |
| Hub reconnect ownership L0→L1→L2 (`client_or_network` awaits Socket.IO; unreachable budget; `/health` via `hubHttpBaseUrl`) | pos-v2.11.2 |

## Criterio de rollout

- Framed application transport requires `PayloadFrame`; plain-JSON hub control
  events are documented exceptions, not a legacy RPC fallback. New clients follow
  [`socketio_client_binary_transport.md`](socketio_client_binary_transport.md).
- Liberar por feature flag, quando aplicavel.
- Promover para default apenas apos compatibilidade validada com clientes.

## Checklist de prontidao para cada item pendente

- Contrato/documentacao atualizado.
- Testes unitarios adicionados.
- Testes de integracao executados.
- Feature flag criada (quando aplicavel) e validada.
- Metricas e logs de observabilidade adicionados.
