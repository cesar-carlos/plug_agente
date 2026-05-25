# Socket Communication Roadmap (Planned Improvements)

## Objetivo

Este roadmap lista apenas evolucoes ainda pendentes.
Itens concluidos foram removidos para evitar ruido.

Estado implementado atual:
`docs/communication/socket_communication_standard.md`.

## Itens planejados (pendentes)


| Item                                                    | Status  | Fase alvo |
| ------------------------------------------------------- | ------- | --------- |
| Testes de integracao end-to-end para limites negociados | planned | Fase 6    |
| Rotacao automatica de chaves de assinatura              | planned | Fase 6    |
| Monitoramento/alertas de payload signing failures       | planned | Fase 6    |
| Homologacao E2E hub-agente para `client_token.getPolicy` (rate limit, retry_after_ms / reset_at) | planned | Fase 6 |


## Itens concluidos (removidos do backlog)


| Item                                                              | Concluido em |
| ----------------------------------------------------------------- | ------------ |
| Plug JSON-RPC `agent.action.*` remoto (incl. `validateRun` + `skipped`), OpenRPC `2.11.2`, fixtures `test/fixtures/rpc/` | v2.11.2 |
| `api_version` + `meta` obrigatorios por contrato                  | v2.1         |
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
| Offload de HMAC-SHA256 para isolate via `compute()` acima de 64 KiB (`PayloadSigner.signFrameAsync`) | pos-v2.11 |
| `trace_id` em `agent:heartbeat` para correlacao de rastreamento distribuido | pos-v2.11 |
| `rpc:stream.pull` registrado para qualquer flag de streaming ativa (nao so backpressure) | pos-v2.11 |
| Codigos terminais vs recuperaveis de `agent:register_error` documentados e implementados | pos-v2.11 |


## Fase 5 - Hardening residual (concluida)

Todos os itens da Fase 5 foram implementados:

- Negociacao real de limites via `TransportLimits` em `ProtocolCapabilities`.
- `PayloadSigner` com HMAC-SHA256, verificacao constant-time, feature flag `enablePayloadSigning` (default **off**).
- Feature flags promovidas para default `true`: `enableClientTokenAuthorization`, `enableSocketApiVersionMeta`, `enableSocketNotificationsContract`, `enableSocketBatchStrictValidation`, `enableSocketSchemaValidation`, `enableSocketCancelMethod`.

## Fase 6 - Observabilidade e operacao

Objetivo:

- Homologar clientes no fluxo encode/compress/decode/decompress.
- Testes de integracao de ponta a ponta para limites negociados e delivery guarantees.
- Automatizar rotacao de chaves de assinatura sem downtime.
- Alertas operacionais para falhas de assinatura.
- Homologar `client_token.getPolicy` E2E com hub real (rate limit, `retry_after_ms`).

## Criterio de rollout

- Manter dual-stack durante migracao.
- Liberar por feature flag, quando aplicavel.
- Promover para default apenas apos compatibilidade validada com clientes.

## Checklist de prontidao para cada item pendente

- Contrato/documentacao atualizado.
- Testes unitarios adicionados.
- Testes de integracao executados.
- Feature flag criada (quando aplicavel) e validada.
- Metricas e logs de observabilidade adicionados.
