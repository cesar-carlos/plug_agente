# Socket Communication Roadmap (Planned Improvements)

## Objetivo

Este documento lista melhorias planejadas para evolucao do protocolo de
comunicacao Socket, sem confundir com o padrao atualmente implementado.

Backlog executavel:
`docs/communication/socket_communication_backlog.md`.

## Status do roadmap

| Item | Status | Fase alvo |
| --- | --- | --- |
| `api_version` + `meta` obrigatorios | planned | Fase 1 |
| Idempotencia (`idempotency_key`) | planned | Fase 2 |
| Timeouts por etapa | planned | Fase 2 |
| Metodo `sql.cancel` | planned | Fase 3 |
| Streaming chunked | planned | Fase 4 |
| Backpressure (`rpc:stream.pull`) | planned | Fase 4 |
| Limites negociados (`max_payload_bytes`, `max_rows`) | planned | Fase 5 |
| Heartbeat de sessao | implemented (agent-side) | Fase 5 |
| Replay protection | implemented (agent-side) | Fase 5 |
| Assinatura opcional de payload | planned | Fase 5 |
| Semantica de notification JSON-RPC | planned | Fase 1 |
| Regras formais de batch (ordem, IDs, atomicidade) | planned | Fase 1 |
| Garantia de entrega por tipo de evento | planned | Fase 2 |
| Connection state recovery (Socket.IO) | implemented (agent-side retry/backoff) | Fase 5 |
| Ciclo de autenticacao na reconexao | implemented (agent-side) | Fase 5 |
| Rate limit e quotas por evento | implemented (agent-side) | Fase 5 |
| Politica de versao e deprecacao | planned | Fase 1 |
| JSON Schema para contratos | planned | Fase 1 |
| Validacao de assinatura de token (JWKS) | planned | Fase 1 |
| Paridade de enforcement no legado | implemented | Transversal |
| Observabilidade de autorizacao (metricas + logs transporte) | implemented | Fase 5 |
| Resumo de autorizacao no dashboard | implemented | Fase 5 |
| Refresh de auth por `token_revoked`/`authentication_failed` | implemented | Fase 5 |
| Revogacao em sessao ativa | planned | Fase 2 |
| Auditoria de token management | planned | Fase 5 |

## Plano Incremental

### Fase 1 - Contrato v2.1

Objetivo:

- Tornar observabilidade e rastreabilidade padrao no contrato v2.

- Adicionar `api_version` e `meta` no contrato v2
- Definir semantica de notification (requests sem `id`)
- Definir regras formais de batch (IDs unicos, ordem de resposta, limites)
- Definir politica de versao e deprecacao do contrato
- Publicar JSON Schema dos payloads principais
- Padronizar contrato obrigatorio de `error.data`
- Definir validacao de token com JWKS (`kid`, issuer, audience, alg allowlist)
- Validacao de payload no boundary do transporte
- Testes de compatibilidade com fallback legado

Entregaveis:

- Novo contrato documentado com exemplos.
- Esquemas JSON versionados para request/response/error/batch.
- Validacao ativa para requests v2 invalidas.
- Contrato de erro padronizado com campos obrigatorios para UX e suporte.

Criterio de aceite:

- Requests v2 sem campos obrigatorios retornam erro padronizado.
- Notifications nao geram resposta por contrato.
- IDs duplicados em batch sao rejeitados com erro de contrato.
- Token com assinatura invalida e rejeitado no boundary.
- Fluxo legado permanece funcional.
- Toda resposta de erro inclui `reason`, `category`, `retryable`,
  `user_message`, `technical_message`, `correlation_id`, `timestamp`.

### Fase 2 - Idempotencia e timeout por etapa

Objetivo:

- Evitar duplicidade e melhorar diagnostico de timeout.

- Incluir `idempotency_key` em metodos SQL
- Distinguir timeout de execucao x timeout de transporte/ack
- Deduplicacao por janela temporal
- Definir garantia de entrega por evento (best effort, ack, retry)
- Definir revogacao com efeito em sessao ativa

Entregaveis:

- Tabela de deduplicacao com TTL configuravel.
- Metricas separadas por tipo de timeout.
- Matriz de entrega por evento publicada no contrato.

Criterio de aceite:

- Retry com mesma chave nao duplica execucao.
- Timeouts de SQL e transporte sao separados em logs/erros.
- Eventos criticos possuem ack/retry definido.
- Token revogado deixa de autorizar novas requests sem exigir reconexao.

### Fase 3 - `sql.cancel`

Objetivo:

- Permitir cancelamento explicito de queries longas.

- Implementar metodo no dispatcher RPC
- Integrar cancelamento ao gateway de execucao
- Mapear erro de cancelamento no catalogo

Entregaveis:

- Metodo `sql.cancel` documentado e funcional.
- Mapeamento de erro de cancelamento no contrato.

Criterio de aceite:

- Cliente recebe confirmacao de cancelamento da execucao ativa.

### Fase 4 - Streaming e backpressure

Objetivo:

- Reduzir latencia e uso de memoria em resultados grandes.

- Enviar resultados grandes em chunks
- Fechamento de stream com evento dedicado
- Controle de consumo pelo cliente

Entregaveis:

- Eventos `rpc:chunk` e `rpc:complete`.
- Controle de janela via `rpc:stream.pull`.

Criterio de aceite:

- Cliente consegue controlar ritmo de consumo sem perda de ordem.

### Fase 5 - Hardening operacional (parcialmente implementada)

Objetivo:

- Aumentar resiliencia e seguranca de sessao.

- Heartbeat e recuperacao de sessao
- Limites de payload negociados
- Protecao contra replay
- Connection state recovery para reconexoes curtas
- Politica de refresh de token no reconnect
- Rate limiting por evento/tenant
- Trilha de auditoria para create/revoke/update de token/policy

Entregaveis:

- Fluxo de heartbeat e reconexao com backoff.
- Rejeicao de replay e payload acima do limite.
- Quotas por evento com codigo de erro padronizado.

Criterio de aceite:

- Sessao se recupera automaticamente apos perda de conexao.
- Requests de replay sao bloqueadas.
- Reconnect com token expirado segue fluxo padronizado.
- Auditoria de mudancas de token esta disponivel para suporte/compliance.

## Mapa rapido de evolucao de eventos

| Evento/Mecanismo | Estado atual | Estado alvo |
| --- | --- | --- |
| `rpc:request` / `rpc:response` | ativo | manter |
| `query:request` / `query:response` | ativo | manter durante migracao |
| `sql.cancel` | nao ativo | Fase 3 |
| `rpc:chunk` / `rpc:complete` | nao ativo | Fase 4 |
| `rpc:stream.pull` | nao ativo | Fase 4 |
| `agent:heartbeat` / `hub:heartbeat_ack` | nao formalizado | Fase 5 |
| notification (request sem `id`) | nao formalizado | Fase 1 |
| connection state recovery | nao ativo | Fase 5 |
| validacao criptografica de token (JWKS) | nao formalizado | Fase 1 |
| enforcement equivalente no legado | ativo | manter |

## Feature Flags Sugeridas

- `enableSocketApiVersionMeta`
- `enableSocketIdempotency`
- `enableSocketTimeoutByStage`
- `enableSocketCancelMethod`
- `enableSocketStreamingChunks`
- `enableSocketBackpressure`
- `enableSocketHeartbeat`
- `enableSocketReplayProtection`
- `enableSocketNotificationsContract`
- `enableSocketBatchStrictValidation`
- `enableSocketDeliveryGuarantees`
- `enableSocketStateRecovery`
- `enableSocketReconnectAuthPolicy`
- `enableSocketRateLimits`
- `enableSocketTokenJwksValidation`
- `enableSocketLegacyEnforcementParity`
- `enableSocketActiveSessionRevocation`

## Criterio de rollout

- Sempre manter dual-stack durante migracao.
- Liberar por flag, em etapas, com monitoramento de erro e latencia.
- Promover para default apenas apos compatibilidade validada com clientes.

### Politica de versao e deprecacao (planejada)

- Suportar no minimo 2 versoes de contrato em paralelo.
- Comunicar deprecacao com antecedencia minima de 1 ciclo de release.
- Bloqueio de versao antiga somente apos janela de migracao concluida.

## Matriz de garantia de entrega (planejada)

| Tipo de evento | Garantia alvo | Mecanismo |
| --- | --- | --- |
| Telemetria/notification | best effort | sem ack |
| Request critico hub -> agente | at least once | ack + retry + idempotencia |
| Response agente -> hub | at least once (controlado) | ack + replay por offset |

## Contratos e schemas (planejado)

Schemas versionados a publicar:

- `rpc.request.schema.json`
- `rpc.response.schema.json`
- `rpc.error.schema.json`
- `rpc.batch.request.schema.json`
- `rpc.batch.response.schema.json`
- `legacy.envelope.v1.schema.json`

Campos obrigatorios planejados em `error.data`:

- `reason`
- `category`
- `retryable`
- `user_message`
- `technical_message`
- `correlation_id`
- `timestamp`

Catalogo central de enums:

- `docs/communication/socket_communication_standard.md`

## Checklist de prontidao por fase

- [ ] Contratos e exemplos atualizados no documento.
- [ ] Testes unitarios da fase adicionados.
- [ ] Testes de integracao com fallback legado executados.
- [ ] Feature flag da fase criada e validada.
- [ ] Metricas e logs de observabilidade adicionados.

## Changelog planejado

### v2.1 (planned)

- `api_version` + `meta` obrigatorios
- idempotencia e timeout por etapa
- `sql.cancel`
- semantica de notification
- regras formais de batch
- politica de versao/deprecacao
- schemas JSON publicados

### v2.2 (planned)

- streaming chunked
- backpressure

### v2.3 (planned)

- heartbeat de sessao
- replay protection
- assinatura opcional de payload
- state recovery
- reconnect auth policy
- rate limiting por evento



