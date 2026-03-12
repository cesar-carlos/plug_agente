# Socket Communication Standard (Current Implementation)

## Objetivo

Este documento descreve **somente o que ja esta implementado** no
projeto para comunicacao Socket.IO entre hub e agente.

## Escopo Atual (implementado)

- Protocolo principal: JSON-RPC 2.0 (`jsonrpc-v2`)
- Compatibilidade legada: envelope v1 (`legacy-envelope-v1`)
- Metodos RPC:
  - `sql.execute`
  - `sql.executeBatch`
- Catalogo padronizado de erros RPC
- Negociacao de capacidades com fallback automatico
- Dual-stack em runtime (v2 e legado em paralelo)

## Status de implementacao

| Item | Status |
| --- | --- |
| JSON-RPC 2.0 (`rpc:request`/`rpc:response`) | implemented |
| Fallback legado (`query:request`/`query:response`) | implemented |
| Metodo `sql.execute` | implemented |
| Metodo `sql.executeBatch` | implemented |
| Catalogo de erros RPC | implemented |
| Negociacao de capacidades | implemented |
| `sql.cancel` | implemented (via feature flag) |
| Streaming chunked | implemented (via feature flag; >500 rows) |
| Streaming direto do banco (SELECT sem params) | implemented (via enableSocketStreamingFromDb) |
| Backpressure | implemented (window_size em rpc:stream.pull controla envio) |
| Notification JSON-RPC (sem resposta) | implemented (via feature flag) |
| Regras estritas de batch (IDs unicos/ordem) | implemented (via feature flag) |
| Garantia de entrega por evento (ack/retry) | implemented (via feature flag) |
| Timeout por etapa (SQL, transporte, ack) | implemented (via feature flag) |
| Idempotencia por `idempotency_key` (sql.execute/batch) | implemented (via feature flag) |
| Connection state recovery | implemented (agent-side retry/backoff) |
| Politica de auth no reconnect | implemented (agent-side) |
| Rate limiting por evento | implemented (agent-side) |
| Schema JSON oficial de contrato | implemented (docs/communication/schemas/) |
| Validacao de schema na entrada (rpc:request) | implemented (via feature flag) |
| Validacao criptografica de token (JWKS) | implemented (via feature flag) |
| Revogacao em sessao ativa | implemented (via feature flag) |
| Paridade de enforcement no legado | implemented |
| Observabilidade de autorizacao (collector allow/deny) | implemented |
| Logs de decisao de autorizacao no transporte (`AUTH`) | implemented |
| Resumo de autorizacao no dashboard (`WebSocketLogViewer`) | implemented |
| Refresh de auth em runtime (`token_revoked`/`authentication_failed`) | implemented |
| Heartbeat de sessao (`agent:heartbeat`/`hub:heartbeat_ack`) | implemented (agent-side) |
| Recovery de conexao curta com retry/backoff | implemented (agent-side) |
| Replay protection por janela de request ID | implemented (agent-side) |
| Auditoria de token management | implemented (via feature flag) |

## Eventos Socket.IO Ativos

### Negociacao

- `agent:register`
  - enviado pelo agente na conexao
  - inclui identificacao e capacidades
- `agent:capabilities`
  - recebido do hub para definir protocolo efetivo

### Heartbeat de sessao

- `agent:heartbeat`
  - enviado periodicamente pelo agente quando protocolo efetivo e v2
- `hub:heartbeat_ack`
  - recebido do hub como confirmacao de heartbeat
  - na ausencia de `ack` por janelas consecutivas, o agente marca conexao como
    stale e aciona fluxo de reconexao

### Requisicoes de execucao

- v2:
  - request: `rpc:request`
  - response: `rpc:response`
- legado:
  - request: `query:request`
  - response: `query:response`

## Mapa rapido de eventos

| Evento | Direcao | Payload esperado | Resposta |
| --- | --- | --- | --- |
| `agent:register` | agente -> hub | identificacao + capacidades | `agent:capabilities` |
| `agent:capabilities` | hub -> agente | capacidades do hub | define protocolo efetivo |
| `rpc:request` | hub -> agente | JSON-RPC 2.0 (`method`, `id`, `params`) | `rpc:response` |
| `query:request` | hub -> agente | envelope legado v1 | `query:response` |
| `rpc:request_ack` | agente -> hub | `{ request_id, received_at }` | (quando `enableSocketDeliveryGuarantees`) |
| `rpc:batch_ack` | agente -> hub | `{ request_ids, received_at }` | (quando `enableSocketDeliveryGuarantees`) |
| `rpc:chunk` | agente -> hub | `{ stream_id, request_id, chunk_index, rows }` | (quando `enableSocketStreamingChunks`) |
| `rpc:complete` | agente -> hub | `{ stream_id, request_id, total_rows }` | (quando `enableSocketStreamingChunks`) |
| `rpc:stream.pull` | hub -> agente | `{ stream_id, window_size }` | (quando `enableSocketBackpressure`) |

## Streaming chunked (quando `enableSocketStreamingChunks` ativo)

Fluxo atual para resultados grandes:

1. Hub envia `rpc:request` com `sql.execute`.
2. Agente inicia execucao; se resultado exceder limite, retorna resposta inicial
   com `stream_id` e emite `rpc:chunk` para cada lote ordenado.
3. Agente emite `rpc:complete` ao finalizar com `total_rows` e resumo.
4. Se `enableSocketBackpressure`: agente espera `rpc:stream.pull` antes de enviar
   proximos chunks; `window_size` controla quantos chunks enviar por pull.

Contratos: `RpcStreamChunk`, `RpcStreamComplete`, `RpcStreamPull` em
`lib/domain/protocol/rpc_stream.dart`.

## Garantia de entrega (quando `enableSocketDeliveryGuarantees` ativo)

| Tipo de evento | Garantia | Mecanismo |
| --- | --- | --- |
| Telemetria/notification | best effort | sem ack |
| Request critico hub -> agente | at least once | `rpc:request_ack` / `rpc:batch_ack` + retry hub + idempotencia |
| Response critico agente -> hub | at least once (controlado) | `emitWithAck` + retry ate 3x em timeout de ack |

## Contrato JSON-RPC 2.0 (v2)

### Fluxo completo (exemplo unico)

1. Hub recebe `agent:register`.
2. Hub responde `agent:capabilities`.
3. Hub envia `rpc:request` com `id: "req-123"`.
4. Agente executa SQL.
5. Agente retorna `rpc:response` de sucesso ou erro com o mesmo `id`.

### Request (`sql.execute`)

```json
{
  "jsonrpc": "2.0",
  "method": "sql.execute",
  "id": "req-123",
  "params": {
    "sql": "SELECT * FROM users WHERE id = :id",
    "params": { "id": 1 },
    "options": {
      "timeout_ms": 30000,
      "max_rows": 50000
    }
  }
}
```

Com extensao v2.1 (quando `enableSocketApiVersionMeta` ativo):

```json
{
  "jsonrpc": "2.0",
  "method": "sql.execute",
  "id": "req-123",
  "params": { "sql": "SELECT 1", "params": {} },
  "api_version": "2.1",
  "meta": {
    "trace_id": "t-abc",
    "request_id": "req-123",
    "agent_id": "agent-01",
    "timestamp": "2026-03-12T10:00:00Z"
  }
}
```

### Response de sucesso

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "result": {
    "execution_id": "exec-456",
    "started_at": "2026-03-12T10:00:00Z",
    "finished_at": "2026-03-12T10:00:01Z",
    "rows": [],
    "row_count": 0,
    "affected_rows": 0,
    "column_metadata": []
  }
}
```

### Response de erro

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "error": {
    "code": -32102,
    "message": "SQL execution failed",
    "data": {
      "type": "https://plugagente.dev/problems/sql-execution-failed",
      "title": "SQL execution failed",
      "status": 500,
      "detail": "Falha ao executar comando SQL",
      "instance": "req-123"
    }
  }
}
```

Com extensao v2.1 (quando `enableSocketApiVersionMeta` ativo):

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "result": { "execution_id": "exec-456", "rows": [], "row_count": 0 },
  "api_version": "2.1",
  "meta": {
    "agent_id": "agent-01",
    "request_id": "req-123",
    "timestamp": "2026-03-12T10:00:01Z"
  }
}
```

## Batch (implementado)

### Request (`sql.executeBatch`)

```json
{
  "jsonrpc": "2.0",
  "method": "sql.executeBatch",
  "id": "batch-001",
  "params": {
    "commands": [
      { "sql": "SELECT * FROM users" },
      { "sql": "SELECT COUNT(*) AS total FROM orders" }
    ],
    "options": {
      "timeout_ms": 30000,
      "max_rows": 50000,
      "transaction": false
    }
  }
}
```

### Response de batch (exemplo)

```json
{
  "jsonrpc": "2.0",
  "id": "batch-001",
  "result": {
    "execution_id": "batch-789",
    "started_at": "2026-03-12T10:00:00Z",
    "finished_at": "2026-03-12T10:00:02Z",
    "items": [
      { "index": 0, "ok": true, "rows": [], "row_count": 0 },
      { "index": 1, "ok": true, "rows": [], "row_count": 1 }
    ],
    "total_commands": 2,
    "successful_commands": 2,
    "failed_commands": 0
  }
}
```

## Catalogo de Erros

### JSON-RPC padrao

- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

### Transporte

- `-32001`: Authentication failed
- `-32002`: Unauthorized
- `-32008`: Timeout
- `-32009`: Invalid payload
- `-32010`: Decoding failed
- `-32011`: Compression failed
- `-32012`: Network error
- `-32013`: Rate limit exceeded
- `-32014`: Replay detected

### Dominio SQL

- `-32101`: SQL validation failed
- `-32102`: SQL execution failed
- `-32103`: Transaction failed
- `-32104`: Connection pool exhausted
- `-32105`: Result too large
- `-32106`: Database connection failed
- `-32107`: Query timeout
- `-32108`: Invalid database config
- `-32109`: Execution not found (sql.cancel)
- `-32110`: Execution cancelled

## Erros acionaveis para clientes

| Codigo | Cenario comum | Acao recomendada no cliente |
| --- | --- | --- |
| `-32700` | JSON malformado | corrigir serializacao JSON e reenviar |
| `-32600` | request invalida | validar contrato antes de enviar |
| `-32601` | metodo inexistente | ajustar nome do metodo para um suportado |
| `-32602` | parametros invalidos | corrigir payload antes de reenviar |
| `-32603` | erro interno | retry com backoff; se persistir, acionar suporte |
| `-32001` | falha de autenticacao | renovar credencial/token e reconectar |
| `-32002` | sem permissao para operacao | ocultar acao na UI e orientar contato com admin |
| `-32008` | timeout | retry com backoff e observabilidade |
| `-32009` | payload invalido | validar schema e encoding antes do envio |
| `-32010` | falha de decode | verificar content-type/encoding e compatibilidade |
| `-32011` | falha de compressao | reenviar sem compressao (fallback) e registrar erro |
| `-32012` | erro de rede | reconectar socket e repetir com controle |
| `-32013` | limite de requests por janela excedido | aplicar backoff e reduzir concorrencia |
| `-32014` | request duplicada (replay) | reenviar com novo `id`/correlation |
| `-32101` | SQL invalido | ajustar query no cliente |
| `-32102` | erro de execucao SQL | exibir erro tecnico e permitir retry manual |
| `-32103` | falha transacional | revisar lote/ordem e repetir operacao com cautela |
| `-32104` | pool de conexoes esgotado | retry com backoff e limitar concorrencia |
| `-32105` | resultado muito grande | reduzir escopo, pagina ou filtrar query |
| `-32106` | falha de conexao ao banco | verificar DSN/credenciais e status do banco |
| `-32107` | query muito demorada | otimizar query ou reduzir escopo |
| `-32108` | configuracao de banco invalida | revisar configuracao e salvar novamente |
| `-32109` | execucao nao encontrada para cancelar | execucao pode ter finalizado ou nunca iniciado |
| `-32110` | execucao cancelada | informar usuario e encerrar fluxo |

## Metodo `sql.cancel` (via feature flag)

Quando `enableSocketCancelMethod` esta ativo, o metodo `sql.cancel` permite
cancelar uma execucao em streaming ativa.

### Request

```json
{
  "jsonrpc": "2.0",
  "method": "sql.cancel",
  "id": "req-cancel",
  "params": {
    "execution_id": "exec-123",
    "request_id": "req-1"
  }
}
```

Pelo menos um de `execution_id` ou `request_id` e obrigatorio.

### Response de sucesso

```json
{
  "jsonrpc": "2.0",
  "id": "req-cancel",
  "result": {
    "cancelled": true,
    "execution_id": "exec-123",
    "request_id": "req-1"
  }
}
```

### Erro quando execucao nao encontrada

```json
{
  "jsonrpc": "2.0",
  "id": "req-cancel",
  "error": {
    "code": -32109,
    "message": "Execution not found",
    "data": {
      "reason": "execution_not_found",
      "category": "database",
      "retryable": false,
      "user_message": "Execucao nao encontrada. Pode ter sido finalizada ou nunca iniciada.",
      "technical_message": "No in-flight execution found to cancel."
    }
  }
}
```

**Nota**: O cancelamento aplica-se apenas a execucoes em streaming (ex.: Playground).
Execucoes via `sql.execute` (nao-streaming) nao sao cancelaveis por este metodo.

## Contrato obrigatorio de erro (`error.data`)

Para padronizar UX e troubleshooting, toda resposta de erro deve incluir:

- `reason`: motivo estruturado do erro (enum estavel para automacao)
- `category`: classe do erro (`validation`, `auth`, `network`, `sql`, `internal`)
- `retryable`: boolean indicando se retry automatico faz sentido
- `user_message`: mensagem amigavel para exibicao na UI
- `technical_message`: detalhe tecnico para log
- `correlation_id`: id para suporte cruzar logs
- `timestamp`: instante UTC no formato ISO-8601

Exemplo:

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "error": {
    "code": -32012,
    "message": "Network error",
    "data": {
      "reason": "socket_disconnected",
      "category": "network",
      "retryable": true,
      "user_message": "Conexao com o hub foi perdida. Tente novamente.",
      "technical_message": "Socket disconnected during rpc:request handling",
      "correlation_id": "corr-3f7d7f25",
      "timestamp": "2026-03-12T12:00:00Z"
    }
  }
}
```

## Catalogo oficial de `category` e `reason`

Os valores abaixo devem ser tratados como o conjunto oficial inicial para
implementacao. Novos valores devem ser adicionados de forma versionada.

### `category`

| Valor | Uso |
| --- | --- |
| `validation` | erro de contrato, parametro ou formato |
| `auth` | autenticacao, autorizacao ou token |
| `network` | conectividade, socket, handshake |
| `transport` | payload, encoding, compressao, framing |
| `sql` | validacao ou execucao SQL |
| `database` | conectividade/configuracao do banco |
| `internal` | falha interna nao categorizada |

### `reason`

| Codigo | `reason` recomendado |
| --- | --- |
| `-32700` | `json_parse_error` |
| `-32600` | `invalid_request` |
| `-32601` | `method_not_found` |
| `-32602` | `invalid_params` |
| `-32603` | `internal_error` |
| `-32001` | `authentication_failed` |
| `-32002` | `unauthorized` |
| `-32008` | `timeout` |
| `-32009` | `invalid_payload` |
| `-32010` | `decoding_failed` |
| `-32011` | `compression_failed` |
| `-32012` | `network_error` |
| `-32013` | `rate_limited` |
| `-32014` | `replay_detected` |
| `-32101` | `sql_validation_failed` |
| `-32102` | `sql_execution_failed` |
| `-32103` | `transaction_failed` |
| `-32104` | `connection_pool_exhausted` |
| `-32105` | `result_too_large` |
| `-32106` | `database_connection_failed` |
| `-32107` | `query_timeout` |
| `-32108` | `invalid_database_config` |

Regras:

- `reason` deve ser estavel e orientado a automacao.
- `message` pode variar menos, mas `reason` e o identificador principal.
- `user_message` pode ser localizado; `reason` nao.

## Politica de erro para UI e logs

### UX (exibicao ao usuario)

- Exibir apenas `user_message` em mensagens de erro.
- Opcionalmente exibir `correlation_id` para o usuario copiar e enviar ao suporte.
- Nunca exibir stack trace, `technical_message` ou detalhes de infraestrutura ao usuario final.
- Para erros `retryable=true`, oferecer acao de "Tentar novamente" na UI.

### Logs (diagnostico e suporte)

- Registrar `technical_message`, `code`, `reason`, `category`, `correlation_id`.
- Preservar contexto suficiente para cruzar logs entre agente, hub e cliente.
- Usar `correlation_id` como chave de correlacao em sistemas de log.

### Retry

- Retry automatico so deve ocorrer quando `retryable=true`.
- Aplicar backoff exponencial em retries automaticos.

## Politica de operacao e quotas

### Reconnect e recovery

- **Reconexao curta**: apos desconexao, o agente tenta reconectar com backoff
  exponencial (2s, 4s, 8s, ate max 10s).
- **Max tentativas**: 3 tentativas por ciclo de recovery.
- **Token expirado**: ao detectar `token_revoked` ou `authentication_failed`, o
  agente tenta refresh via AuthProvider e reconecta com token renovado.
- **Heartbeat**: `agent:heartbeat` a cada 20s; ausencia de `hub:heartbeat_ack`
  em 2 janelas consecutivas aciona reconexao.

### Rate limiting (agent-side)

| Parametro | Valor padrao | Descricao |
| --- | --- | --- |
| `rateLimitWindow` | 1 minuto | Janela deslizante para contagem |
| `maxRequestsPerWindow` | 120 | Maximo de `rpc:request` por janela |
| Codigo de erro | `-32013` (`rate_limited`) | HTTP 429 |

### Replay protection

| Parametro | Valor padrao | Descricao |
| --- | --- | --- |
| `replayWindow` | 2 minutos | Janela de validade de `request.id` |
| Codigo de erro | `-32014` (`replay_detected`) | HTTP 409 |

### Codigos de erro finais (transport)

| Codigo | `reason` | `category` | `retryable` |
| --- | --- | --- | --- |
| `-32013` | `rate_limited` | transport | false |
| `-32014` | `replay_detected` | transport | false |

## Compatibilidade de erro legado x v2

Enquanto dual-stack estiver ativo, a semantica para usuario final deve ser
equivalente:

| Cenario | Legado (`query:response`) | V2 (`rpc:response`) |
| --- | --- | --- |
| payload invalido | erro padronizado no envelope | `code=-32009` |
| auth/token invalido | erro padronizado no envelope | `code=-32001` |
| sem permissao | erro padronizado no envelope | `code=-32002` |
| sql invalido | erro padronizado no envelope | `code=-32101` |
| sql falhou | erro padronizado no envelope | `code=-32102` |
| timeout | erro padronizado no envelope | `code=-32008`/`-32107` |

Regra de ouro: requests equivalentes em legado e v2 devem resultar em
mensagens de negocio equivalentes para o usuario.

## Idioma e localizacao de erros

- `message`, `reason`, `technical_message`: manter em ingles estavel
  (orientado a contrato e logs).
- `user_message`: texto amigavel localizavel (pt-BR na UI atual).
- Evitar mistura de idiomas no mesmo campo.

## Capabilities (negociacao atual)

Exemplo de capacidades anunciadas:

```json
{
  "protocols": ["jsonrpc-v2", "legacy-envelope-v1"],
  "encodings": ["json", "msgpack"],
  "compressions": ["gzip", "none"],
  "extensions": {
    "batchSupport": true,
    "binaryPayload": true,
    "streamingResults": false
  }
}
```

## Compatibilidade e Fallback

- O agente permanece escutando eventos legados e v2.
- Se o hub nao suportar v2, o agente usa legado automaticamente.
- Respostas seguem o protocolo da requisicao recebida.

### Exemplo de payload legado (v1)

```json
{
  "v": 1,
  "type": "query_request",
  "requestId": "req-legacy-001",
  "agentId": "agent-01",
  "timestamp": "2026-03-12T10:00:00Z",
  "cmp": "none",
  "contentType": "json",
  "payloadBytes": [
    { "query": "SELECT * FROM users", "parameters": {} }
  ]
}
```

## Observabilidade de autorizacao (implementado)

- Coleta de metricas de autorizacao em memoria (allow/deny, por operacao, recurso e motivo).
- Logs estruturados no transporte para decisoes de autorizacao no fluxo RPC (`authorization.allowed` e `authorization.denied`).
- Exibicao de resumo de autorizacao no dashboard via `WebSocketLogViewer`.
- Quando o RPC retorna `authentication_failed` ou `token_revoked`, o transporte
  dispara callback de refresh de token/reconexao.

## Limites operacionais atuais

- `options.timeout_ms` suportado em `sql.execute` e `sql.executeBatch`.
- `options.max_rows` suportado em `sql.execute` e `sql.executeBatch`.
- Para fluxos sem streaming, payload segue request/response unico.
- Limites finos por transporte ainda nao sao negociados no contrato atual.

## Limitacoes e observacoes do estado atual

- Metodo `sql.cancel` disponivel via feature flag `enableSocketCancelMethod`
  (cancela execucao em streaming ativa; execucoes nao-streaming nao sao
  cancelaveis).
- Streaming chunked: ativo via `enableSocketStreamingChunks`; resultados
  com >500 linhas sao enviados em chunks (rpc:chunk, rpc:complete).
- Backpressure: implementado quando `enableSocketBackpressure`; o hub envia
  `rpc:stream.pull` com `window_size` para controlar quantos chunks o agente
  envia por vez; credito inicial de 1 chunk.
- `api_version`/`meta` disponiveis via feature flag `enableSocketApiVersionMeta`.
- Notification JSON-RPC (sem `id`) formalizada via `enableSocketNotificationsContract`.
- Regras estritas de batch (IDs unicos, limite 32) via `enableSocketBatchStrictValidation`.
- Timeout por etapa (SQL, transporte, ack) disponivel via
  `enableSocketTimeoutByStage`; erros incluem `reason` especifico
  (`query_timeout`, `transport_timeout`, `ack_timeout`).
- Garantia de entrega por tipo de evento disponivel via
  `enableSocketDeliveryGuarantees`; ver tabela abaixo quando ativo.
- Connection state recovery com retry/backoff esta ativo agent-side.
- Politica de refresh/auth no reconnect esta ativa agent-side.
- Rate limits/quotas por evento estao ativos agent-side.
- Schemas JSON publicados em `docs/communication/schemas/`. Validacao automatica
  na entrada disponivel via `enableSocketSchemaValidation`.
- Validacao criptografica de token (issuer/audience/kid/alg) disponivel via
  `enableSocketJwksValidation`; JWKS URL derivado de `serverUrl/.well-known/jwks.json`
  ou override por `JWKS_URL` (env). Opcional: `JWKS_ISSUER`, `JWKS_AUDIENCE`.
- Revogacao de token com efeito em sessao ativa disponivel via
  `enableSocketRevokedTokenInSession`; tokens revogados sao armazenados em
  memoria com TTL e rejeitados em novas requests sem exigir reconexao.
- Trilha de auditoria para token management (create/revoke/revoked_in_session)
  disponivel via `enableTokenAudit`; persistencia em JSONL.

## Checklist de homologacao do cliente

- [ ] Executa fluxo v2 completo (`agent:register` -> `rpc:request` -> `rpc:response`).
- [ ] Trata erro JSON-RPC em vez de assumir sempre `result`.
- [ ] Homologa `sql.execute` com sucesso e com falha SQL.
- [ ] Homologa `sql.executeBatch` com itens de retorno.
- [ ] Valida fallback para protocolo legado quando v2 nao estiver disponivel.
- [ ] Homologa erros de payload invalido (`-32009`) e decode (`-32010`).
- [ ] Homologa falha de auth (`-32001`) e permissao (`-32002`).
- [ ] Valida regra de retry somente quando `retryable=true`.
- [ ] Exibe `user_message` ao usuario e registra `correlation_id` para suporte.
- [ ] Garante equivalencia de comportamento entre legado e v2 para mesmos cenarios.

## Changelog do protocolo (implementado)

### `v2.0`

- Introducao de JSON-RPC 2.0 no transporte Socket.IO.
- Inclusao de `sql.execute` e `sql.executeBatch`.
- Catalogo de erros padronizado e mapeamento de failures.
- Negociacao de capacidades com fallback para legado.

## Schemas JSON (contrato)

- `docs/communication/schemas/rpc.request.schema.json`
- `docs/communication/schemas/rpc.response.schema.json`
- `docs/communication/schemas/rpc.error.schema.json`
- `docs/communication/schemas/rpc.batch.request.schema.json`
- `docs/communication/schemas/rpc.batch.response.schema.json`
- `docs/communication/schemas/legacy.envelope.v1.schema.json`

## Referencias internas

- Modelos RPC: `lib/domain/protocol/`
- Dispatcher RPC: `lib/application/rpc/rpc_method_dispatcher.dart`
- Transporte: `lib/infrastructure/external_services/socket_io_transport_client_v2.dart`
- Negociacao: `lib/application/services/protocol_negotiator.dart`
- Evolucao pendente: `docs/communication/socket_communication_roadmap.md`





