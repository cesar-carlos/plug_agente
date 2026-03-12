# Socket Communication Backlog (Execution Plan)

## Objetivo

Este backlog converte o roadmap em itens executaveis por fase, com escopo
tecnico, criterios de aceite e plano de testes.

Plano complementar de autorizacao por cliente foi concluido e incorporado neste
backlog e no `socket_communication_standard.md` (arquivo dedicado removido para
evitar duplicidade de fonte de verdade).

## Regras de execucao

- Manter dual-stack (`jsonrpc-v2` + legado) durante toda migracao.
- Liberar cada fase por feature flag.
- Nao quebrar contratos atuais sem janela de deprecacao documentada.
- Enquanto legado estiver ativo, aplicar as mesmas regras de seguranca e
  autorizacao nos dois fluxos (`rpc:request` e `query:request`).

## Ticket 01 - Contrato v2.1 base e schemas

- **Fase**: 1
- **Prioridade**: alta
- **Feature flags**:
  - `enableSocketApiVersionMeta`
  - `enableSocketNotificationsContract`
  - `enableSocketBatchStrictValidation`

### Escopo tecnico

- Adicionar `api_version` e `meta` nos modelos RPC v2.
- Formalizar notification JSON-RPC (request sem `id`, sem response).
- Formalizar batch:
  - IDs unicos no mesmo lote
  - regra de ordenacao de resposta
  - limite de tamanho/quantidade
- Publicar schemas JSON versionados:
  - `rpc.request.schema.json`
  - `rpc.response.schema.json`
  - `rpc.error.schema.json`
  - `rpc.batch.request.schema.json`
  - `rpc.batch.response.schema.json`
  - `legacy.envelope.v1.schema.json`
- Padronizar `error.data` com campos obrigatorios para UX e suporte.
- Definir validacao criptografica de token (issuer, audience, `kid`, algoritmo).

### Criterios de aceite

- Requests v2 invalidas retornam erro padronizado.
- Notification valida nao retorna response.
- Batch com IDs duplicados retorna erro de contrato.
- Schemas publicados e usados em validacao automatica.
- Validacao de token invalido/assinatura invalida bloqueia request.
- Toda resposta de erro inclui campos obrigatorios de UX/suporte.

### Testes minimos

- Unit: validacao de contrato request/response/error.
- Unit: regras de notification.
- Unit: batch strict (duplicidade, limites, ordem).
- Integration: fallback legado continua funcional.

### Subtarefas por camada

- **Domain**
  - Atualizar `RpcRequest`/`RpcResponse` com `apiVersion` e `meta`.
  - Criar modelos para metadados de protocolo (trace/request/agent/timestamp).
  - Definir regras de batch (IDs unicos e limites).
  - Definir contrato estavel de `error.data`.
- **Application**
  - Validar contrato no dispatcher antes de executar metodo.
  - Rejeitar notification para metodos que exigem resposta.
  - Centralizar erros de validacao de contrato em mapper unico.
  - Garantir derivacao consistente de `user_message` e `technical_message`.
- **Infrastructure**
  - Aplicar validacao de schema na entrada de `rpc:request`.
  - Manter adapter legado sem exigir campos novos.
  - Publicar schemas JSON versionados em pasta de contrato.
  - Integrar validacao de token via JWKS (cache + rotacao por `kid`).
- **Test**
  - Testar requests validas e invalidas por schema.
  - Testar notification sem `id` e ausencia de resposta.
  - Testar batch com IDs duplicados e lotes acima do limite.
  - Testar presenca de `correlation_id` e `retryable` em erros.
- **Docs**
  - Atualizar exemplos de `socket_communication_standard.md`.
  - Atualizar status de fase no roadmap apos entrega.
  - Publicar policy de UX/log de erro.

## Ticket 02 - Idempotencia e timeout por etapa

- **Fase**: 2
- **Prioridade**: alta
- **Feature flags**:
  - `enableSocketIdempotency`
  - `enableSocketTimeoutByStage`
  - `enableSocketDeliveryGuarantees`

### Escopo tecnico

- Incluir `idempotency_key` em `sql.execute` e `sql.executeBatch`.
- Implementar deduplicacao com TTL configuravel.
- Separar timeout por etapa:
  - SQL (`timeout_ms`)
  - transporte
  - ack
- Definir garantia de entrega por evento (best effort, ack, retry).

### Criterios de aceite

- Retry com mesma chave nao duplica execucao.
- Timeouts sao classificados por tipo no erro/log.
- Eventos criticos possuem ack/retry definido.

### Testes minimos

- Unit: deduplicacao por chave e TTL.
- Unit: mapeamento de erro por timeout.
- Integration: perda de ack com retry controlado.

### Subtarefas por camada

- **Domain**
  - Adicionar `idempotencyKey` em contratos de `sql.execute` e batch.
  - Modelar estrutura de timeout por etapa.
- **Application**
  - Resolver request deduplicada retornando resultado anterior.
  - Separar falhas por tipo: SQL timeout, transport timeout e ack timeout.
  - Definir matriz de entrega por tipo de evento.
  - Definir policy de revogacao em sessao ativa (revalidacao por request).
- **Infrastructure**
  - Implementar store de idempotencia com TTL.
  - Implementar retry com ack para eventos criticos.
  - Instrumentar logs/metrica por timeout e tentativas.
- **Test**
  - Retry com mesma chave sem duplicar execucao.
  - Expiracao de TTL e nova execucao apos janela.
  - Falha de ack com retry e finalizacao consistente.
- **Docs**
  - Adicionar tabela de garantia de entrega no standard quando ativo.
  - Atualizar limite e comportamento de retry em docs de integracao.

## Ticket 03 - Metodo `sql.cancel`

- **Fase**: 3
- **Prioridade**: alta
- **Feature flags**:
  - `enableSocketCancelMethod`

### Escopo tecnico

- Adicionar rota `sql.cancel` no dispatcher.
- Suportar cancelamento por `execution_id` e/ou `request_id`.
- Integrar cancelamento ao gateway de execucao/streaming.
- Mapear erro de cancelamento no catalogo.

### Criterios de aceite

- Cancelamento de execucao ativa retorna confirmacao consistente.
- Cancelamento de execucao inexistente retorna erro claro.

### Testes minimos

- Unit: request/response de `sql.cancel`.
- Integration: cancelamento durante query longa.
- Integration: corrida entre finalizar e cancelar.

### Subtarefas por camada

- **Domain**
  - Criar/validar contrato de `sql.cancel` (params/result/error).
  - Padronizar codigo de erro para cancelamento.
- **Application**
  - Implementar handler `sql.cancel` no dispatcher.
  - Correlacionar `execution_id` e `request_id` com execucoes ativas.
- **Infrastructure**
  - Adicionar cancelamento no gateway de query e fluxo de streaming.
  - Garantir limpeza de estado apos cancelamento.
- **Test**
  - Cancelamento valido com confirmacao.
  - Cancelamento de execucao inexistente.
  - Corrida entre resposta final e cancelamento concorrente.
- **Docs**
  - Mover `sql.cancel` de planned para implemented no standard.
  - Atualizar exemplos de erro acionavel para cancelamento.

## Ticket 04 - Streaming chunked e backpressure

- **Fase**: 4
- **Prioridade**: media-alta
- **Status**: em andamento (observabilidade de autorizacao ja implementada)
- **Feature flags**:
  - `enableSocketHeartbeat`
  - `enableSocketStateRecovery`
  - `enableSocketReconnectAuthPolicy`
  - `enableSocketRateLimits`
  - `enableSocketReplayProtection`
`n### Ja implementado nesta fase
`n- Metricas de autorizacao (allow/deny por operacao, recurso e motivo).
- Logs estruturados de decisao de autorizacao no transporte RPC.
- Resumo de autorizacao no dashboard (`WebSocketLogViewer`).
  - `enableSocketStreamingChunks`
  - `enableSocketBackpressure`

### Escopo tecnico

- Implementar eventos:
  - `rpc:chunk`
  - `rpc:complete`
  - `rpc:stream.pull`
- Quebrar resultados grandes em chunks ordenados.
- Aplicar controle de janela (`window_size`) no envio.

### Criterios de aceite

- Resultados grandes nao exigem payload unico.
- Cliente controla ritmo de consumo sem perder ordem.

### Testes minimos

- Unit: serializacao de chunk/complete/pull.
- Integration: stream completo com multiplos chunks.
- Integration: cliente lento (backpressure efetivo).

### Subtarefas por camada

- **Domain**
  - Definir contratos para `rpc:chunk`, `rpc:complete` e `rpc:stream.pull`.
  - Definir metadados de stream (`stream_id`, `chunk_index`, `total_chunks`).
- **Application**
  - Orquestrar leitura por lotes com controle de janela.
  - Encerrar stream de forma deterministica com resumo final.
- **Infrastructure**
  - Implementar emissao de chunks ordenados.
  - Implementar fluxo de backpressure por `window_size`.
  - Garantir limites de memoria em streams longas.
- **Test**
  - Ordem de chunk e consistencia de totalizacao.
  - Cliente lento sem perda e sem overflow.
  - Cancelamento de stream durante envio.
- **Docs**
  - Adicionar fluxo oficial de streaming no standard quando ativo.
  - Atualizar mapa de eventos com novos eventos de stream.

## Ticket 05 - Hardening de sessao e seguranca

- **Fase**: 5
- **Prioridade**: media-alta
- **Status**: em andamento (observabilidade de autorizacao ja implementada)
- **Feature flags**:
  - `enableSocketHeartbeat`
  - `enableSocketStateRecovery`
  - `enableSocketReconnectAuthPolicy`
  - `enableSocketRateLimits`
  - `enableSocketReplayProtection`

### Ja implementado nesta fase

- Metricas de autorizacao (allow/deny por operacao, recurso e motivo).
- Logs estruturados de decisao de autorizacao no transporte RPC.
- Resumo de autorizacao no dashboard (`WebSocketLogViewer`).
- Disparo de refresh/reconnect de auth quando RPC retorna
  `authentication_failed` ou `token_revoked`.
- Heartbeat no agente com `agent:heartbeat` e monitoramento de
  `hub:heartbeat_ack` para detectar conexao stale e acionar reconexao.
- Recovery de reconexao curta no `ConnectionProvider` com retry exponencial,
  backoff e reutilizacao do ultimo contexto de conexao valido.
- Rate limiting por janela no transporte RPC (`rpc:request`).
- Replay protection por `request.id` com TTL para evitar duplicidade acidental.

### Escopo tecnico

- Heartbeat formal:
  - `agent:heartbeat`
  - `hub:heartbeat_ack`
- Connection state recovery para desconexoes curtas.
- Politica de auth no reconnect (refresh/retry/erro padrao).
- Rate limiting por evento/tenant.
- Replay protection e validacao de janela temporal.
- Auditoria de token management (create/revoke/update policy).

### Criterios de aceite

- Sessao recupera apos reconexao curta sem perda critica.
- Requests de replay sao rejeitadas.
- Quotas por evento aplicadas com erro padronizado.
- Token revogado em sessao ativa deixa de autorizar novas operacoes.

### Testes minimos

- Integration: reconnect com recuperacao de estado.
- Integration: token expirado no reconnect.
- Integration: rate limit por evento.
- Chaos: oscilacao de rede e reconexao com backoff.

### Subtarefas por camada

- **Domain**
  - Formalizar erros para rate limit, replay e auth reconnect.
  - Formalizar metadados minimos de sessao/offset.
- **Application**
  - Definir politica de reconnect e refresh de token.
  - Definir comportamento para replay detectado.
- **Infrastructure**
  - Implementar heartbeat e timeout de sessao.
  - Ativar connection state recovery quando suportado.
  - Implementar rate limiting por evento/tenant.
  - Implementar replay protection por janela de validade.
  - Persistir trilha de auditoria de token management.
- **Test**
  - Recuperacao de estado em reconexao curta.
  - Reconnect com token expirado e fluxo de renovacao.
  - Bloqueio de replay e resposta de erro esperada.
  - Quotas aplicadas por evento com reset de janela.
- **Docs**
  - Atualizar politica de operacao no standard.
  - Publicar limites de quotas e codigos de erro finais.
  - Revisar tabela de erros acionaveis conforme novos codigos.

## Ticket 06 - Paridade de enforcement no legado

- **Fase**: transversal (1-5)
- **Prioridade**: alta
- **Status**: concluido (enforcement aplicado em `rpc:request` e
  `query:request`)
- **Feature flags**:
  - `enableSocketLegacyEnforcementParity`

### Escopo tecnico

- Garantir que todas as regras de autenticacao/autorizacao do fluxo v2 sejam
  aplicadas no fluxo legado (`query:request`) enquanto dual-stack estiver ativo.
- Evitar bypass de policy por escolha de protocolo.

### Criterios de aceite

- Requests equivalentes em v2 e legado resultam na mesma decisao de
  autorizacao.
- Nao existe caminho legado sem enforcement durante migracao.

### Testes minimos

- Integration: mesma policy, mesmo resultado, em v2 e legado.
- Integration: token revogado bloqueia v2 e legado.
- Integration: erros equivalentes em v2 e legado preservam `reason` e
  `user_message` de negocio.

### Subtarefas por camada

- **Domain**
  - Definir contrato unico de decisao de autorizacao reutilizavel por v2 e
    legado.
  - Garantir mesma matriz de erro (`unauthorized`) para ambos os protocolos.
- **Application**
  - Extrair enforcement para componente compartilhado (evitar regra duplicada).
  - Aplicar componente compartilhado em handlers v2 e legado.
- **Infrastructure**
  - Garantir que `query:request` percorre o mesmo pipeline de validacao de
    autenticacao/autorizacao.
  - Bloquear bypass por evento legado direto.
- **Test**
  - Testes de paridade (mesmo input -> mesma decisao) entre `rpc:request` e
    `query:request`.
  - Testes de regressao para evitar divergencia futura entre os dois caminhos.
  - Testes de equivalencia de erro entre legado e v2.
- **Docs**
  - Atualizar `socket_communication_standard.md` com regra de paridade ativa
    quando implementada.
  - Atualizar `socket_communication_roadmap.md` removendo item de paridade.

## Ordem sugerida de execucao

1. Ticket 01
2. Ticket 02
3. Ticket 03
4. Ticket 04
5. Ticket 05
6. Ticket 06 (transversal em paralelo com os demais)

## Definition of Done (por ticket)

- [ ] Codigo implementado com compatibilidade legado preservada.
- [ ] Feature flag criada e documentada.
- [ ] Testes da fase passando em CI.
- [ ] Atualizacao dos documentos:
  - `socket_communication_standard.md` (se virou implementado)
  - `socket_communication_roadmap.md` (status atualizado)



