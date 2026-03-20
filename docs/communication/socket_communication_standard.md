# Socket Communication Standard (Current Implementation)

## Objetivo

Este documento descreve **somente o que ja esta implementado** no
projeto para comunicacao Socket.IO entre hub e agente.

O guia normativo para clientes que publicam ou consomem eventos no transporte
binario esta documentado em
`docs/communication/socketio_client_binary_transport.md`.

## Escopo Atual (implementado)

- Protocolo principal: JSON-RPC 2.0 (`jsonrpc-v2`)
- Metodos RPC:
  - `sql.execute`
  - `sql.executeBatch`
  - `sql.cancel` (feature flag `enableSocketCancelMethod`)
  - `rpc.discover`
- Catalogo padronizado de erros RPC
- Negociacao de capacidades

## Status de implementacao

| Item                                                                 | Status                                                             |
| -------------------------------------------------------------------- | ------------------------------------------------------------------ |
| JSON-RPC 2.0 (`rpc:request`/`rpc:response`)                          | implemented                                                        |
| Metodo `sql.execute`                                                 | implemented                                                        |
| Metodo `sql.executeBatch`                                            | implemented                                                        |
| Catalogo de erros RPC                                                | implemented                                                        |
| Negociacao de capacidades                                            | implemented                                                        |
| Transporte binario em `PayloadFrame`                                 | implemented (default com `enableBinaryPayload`)                    |
| Compressao GZIP na borda de transporte                               | implemented (por threshold; fallback `cmp: none`)                  |
| Compatibilidade de leitura para payload JSON cru                     | implemented (temporario para rollout/homologacao)                  |
| `sql.cancel`                                                         | implemented (via feature flag)                                     |
| Streaming chunked                                                    | implemented (via feature flag; acima de `streaming_row_threshold`) |
| Streaming direto do banco (SELECT sem params)                        | implemented (via enableSocketStreamingFromDb)                      |
| Backpressure                                                         | implemented (window_size em rpc:stream.pull controla envio)        |
| Notification JSON-RPC (sem resposta)                                 | implemented (via feature flag); contrato formal                    |
| Regras estritas de batch (IDs unicos/ordem)                          | implemented (via feature flag); contrato formal                    |
| Garantia de entrega por evento (ack/retry)                           | implemented (via feature flag)                                     |
| Timeout por etapa (SQL, transporte, ack)                             | implemented (via feature flag)                                     |
| Idempotencia por `idempotency_key` (sql.execute/batch)               | implemented (via feature flag)                                     |
| Connection state recovery                                            | implemented (agent-side retry/backoff)                             |
| Politica de auth no reconnect                                        | implemented (agent-side)                                           |
| Rate limiting por evento                                             | implemented (agent-side)                                           |
| Schema JSON oficial de contrato                                      | implemented (envelope + params + streaming)                        |
| Schema de params por metodo (sql.execute/batch/cancel)               | implemented (docs/communication/schemas/)                          |
| Schema de streaming (chunk/complete/pull)                            | implemented (docs/communication/schemas/)                          |
| Politica de versao e deprecacao                                      | implemented (neste documento)                                      |
| Limites negociados por transporte                                    | implemented (negociacao via TransportLimits no handshake)          |
| Assinatura opcional de payload                                       | implemented (HMAC-SHA256; feature flag `enablePayloadSigning`)     |
| Validacao de schema na entrada (rpc:request)                         | implemented (via feature flag)                                     |
| Client token authorization (opaco + hash lookup)                     | implemented (default on)                                           |
| Validacao criptografica de token (JWKS)                              | implemented (via feature flag; fallback)                           |
| Revogacao em sessao ativa                                            | implemented (via feature flag)                                     |
| Observabilidade de autorizacao (collector allow/deny)                | implemented                                                        |
| Logs de decisao de autorizacao no transporte (`AUTH`)                | implemented                                                        |
| Resumo de autorizacao no dashboard (`WebSocketLogViewer`)            | implemented                                                        |
| Refresh de auth em runtime (`token_revoked`/`authentication_failed`) | implemented                                                        |
| Heartbeat de sessao (`agent:heartbeat`/`hub:heartbeat_ack`)          | implemented (agent-side)                                           |
| Recovery de conexao curta com retry/backoff                          | implemented (agent-side)                                           |
| Replay protection por janela de request ID                           | implemented (agent-side)                                           |
| Auditoria de token management                                        | implemented (via feature flag)                                     |

## Plug JSON-RPC Profile

O transporte usa JSON-RPC 2.0 como base, mas o contrato operacional deste
projeto e o **Plug JSON-RPC Profile**.

Esse profile formaliza extensoes que nao fazem parte do JSON-RPC puro:

- compatibilidade opcional para notification com `id: null`
- batch com validacao estrita e ordenacao estavel de responses
- metadata operacional em `api_version` + `meta`
- payload de erro estruturado em `error.data`
- limites negociados no handshake
- paginacao por `page/page_size` (offset; `ORDER BY` opcional) e por `cursor`
  keyset (`ORDER BY` obrigatorio para estabilidade)

As semanticas ativas podem ser anunciadas em `capabilities.extensions` no
handshake.

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

- request: `rpc:request`
- response: `rpc:response`

## Mapa rapido de eventos

| Evento               | Direcao       | Payload esperado                               | Resposta                                  |
| -------------------- | ------------- | ---------------------------------------------- | ----------------------------------------- |
| `agent:register`     | agente -> hub | `PayloadFrame<{ agentId, timestamp, capabilities }>` | `agent:capabilities`                 |
| `agent:capabilities` | hub -> agente | `PayloadFrame<{ capabilities }>`               | define protocolo efetivo                  |

**Timeout de capabilities:** Se o hub nao responder com `agent:capabilities` dentro
de um tempo limite (ex.: 8 s) apos `agent:register`, o agente reenvia `agent:register`
ate N vezes (ex.: 2). Apos esgotar as tentativas, o agente força reconexao.

**Readiness:** O hub nao deve enviar `rpc:request` antes de o agente ter recebido
`agent:capabilities`. O agente so considera o protocolo pronto apos a negociacao
completa. O `connect` pode retornar sucesso assim que o transporte Socket.IO
estabelece conexao; o agente envia `agent:register` e aguarda `agent:capabilities`
antes de aceitar RPCs.
| `rpc:request`        | hub -> agente | `PayloadFrame<JSON-RPC 2.0 request>`           | `rpc:response`                            |
| `rpc:request_ack`    | agente -> hub | `PayloadFrame<{ request_id, received_at }>`    | (quando `enableSocketDeliveryGuarantees`) |
| `rpc:batch_ack`      | agente -> hub | `PayloadFrame<{ request_ids, received_at }>`   | (quando `enableSocketDeliveryGuarantees`) |
| `rpc:chunk`          | agente -> hub | `PayloadFrame<{ stream_id, request_id, chunk_index, rows }>` | (quando `enableSocketStreamingChunks`) |
| `rpc:complete`       | agente -> hub | `PayloadFrame<{ stream_id, request_id, total_rows }>` | (quando `enableSocketStreamingChunks`) |
| `rpc:stream.pull`    | hub -> agente | `PayloadFrame<{ stream_id, window_size }>`     | (quando `enableSocketBackpressure`)       |

## Camadas do transporte

O padrao fisico da comunicacao agora tem duas camadas:

1. **Payload logico**
   - envelope JSON-RPC, handshake, heartbeat, ack ou evento de streaming.
2. **Payload fisico**
   - o payload logico e serializado em JSON UTF-8, opcionalmente comprimido com
     GZIP e empacotado em `PayloadFrame`.

Fluxo de saida implementado:

1. montar o payload logico;
2. serializar em bytes (`enc: json`);
3. aplicar compressao quando o tamanho atingir `compressionThreshold`;
4. montar `PayloadFrame` com `originalSize`, `compressedSize`, `traceId` e
   `requestId`;
5. assinar o frame quando `enablePayloadSigning` estiver ativo;
6. emitir via Socket.IO.

Fluxo de entrada implementado:

1. receber `PayloadFrame`;
2. validar algoritmo, tamanhos e razao maxima de expansao;
3. verificar assinatura do frame quando presente;
4. descomprimir quando `cmp == gzip`;
5. decodificar o payload logico;
6. validar schema/contrato e despachar.

## Arquivos e payloads binarios de negocio

O transporte binario implementado e o **frame fisico** da mensagem. Ele nao
significa que existe um metodo RPC generico de upload/download de arquivo.

Regras atuais:

- nao existe API dedicada de transferencia de arquivo no contrato publicado;
- se um metodo de negocio precisar carregar conteudo de arquivo, esse conteudo
  deve primeiro ser serializado no payload logico do metodo;
- depois disso, **a mensagem inteira** segue o mesmo processo padrao:
  serializacao -> compressao -> frame binario;
- clientes nao devem tentar “pular” o `PayloadFrame` e enviar bytes crus fora
  do contrato Socket.IO/JSON-RPC.

Para cargas grandes, a recomendacao operacional e usar chunking no nivel do
metodo de negocio, sem abrir excecao para o transporte.

## Streaming chunked (quando `enableSocketStreamingChunks` ativo)

Fluxo atual para resultados grandes:

1. Hub envia `rpc:request` com `sql.execute`.
2. Agente inicia execucao; se resultado exceder limite, retorna resposta inicial
   com `stream_id` e emite `rpc:chunk` para cada lote ordenado.
3. Agente emite `rpc:complete` ao finalizar com `total_rows` e resumo.
4. Se `enableSocketBackpressure`: agente espera `rpc:stream.pull` antes de enviar
   proximos chunks; `window_size` controla quantos chunks enviar por pull.
5. **Overflow de buffer**: se a fila de chunks atingir o limite (`maxBackpressureChunkQueueSize`)
   e o hub nao enviar `rpc:stream.pull` a tempo, o agente **nao descarta** chunks silenciosamente.
   Em vez disso, cancela o stream e retorna erro RPC `resultTooLarge` (`-32105`) com
   `reason: backpressure_overflow`. O hub deve consumir mais rapido ou aumentar `window_size`.

Contratos: `RpcStreamChunk`, `RpcStreamComplete`, `RpcStreamPull` em
`lib/domain/protocol/rpc_stream.dart`.

## Garantia de entrega (quando `enableSocketDeliveryGuarantees` ativo)

| Tipo de evento                 | Garantia                   | Mecanismo                                                      |
| ------------------------------ | -------------------------- | -------------------------------------------------------------- |
| Telemetria/notification        | best effort                | sem ack                                                        |
| Request critico hub -> agente  | at least once              | `rpc:request_ack` / `rpc:batch_ack` + retry hub + idempotencia |
| Response critico agente -> hub | at least once (controlado) | `emitWithAck` + retry ate 3x em timeout de ack                 |

## Notification JSON-RPC (contrato formal)

Uma **notification** e um request JSON-RPC 2.0 sem campo `id`. O agente
**nao deve** retornar response para notifications.

### Regras

- Request sem `id` (ou `id: null`) e tratado como notification.
- O agente processa a notification mas **nao emite** `rpc:response`.
- Notifications nao contam para idempotencia (`idempotency_key` ignorado).
- Notifications nao recebem `rpc:request_ack` (delivery guarantee = best effort).
- Em batch, notifications sao processadas mas nao geram item no array de response.

### Exemplo

```json
{
  "jsonrpc": "2.0",
  "method": "sql.execute",
  "params": {
    "sql": "INSERT INTO logs (msg) VALUES ('ping')"
  }
}
```

### Feature flag

- `enableSocketNotificationsContract`: quando ativo, o agente aplica
  as regras acima de forma estrita. Quando desativado, notifications
  ainda sao aceitas mas podem gerar response vazio.

## Regras formais de batch (contrato)

### Limites

| Parametro              | Valor       | Descricao                                             |
| ---------------------- | ----------- | ----------------------------------------------------- |
| Max itens por batch    | 32          | Acima disso, retorna `-32600` (invalid request)       |
| IDs unicos             | obrigatorio | IDs duplicados retornam `-32600` (quando strict mode) |
| Ordem de processamento | sequencial  | Respostas na mesma ordem dos requests                 |
| Notifications em batch | permitido   | Itens sem `id` nao geram response                     |

### Regras de validacao (strict mode)

Quando `enableSocketBatchStrictValidation` esta ativo:

1. Batch vazio: rejeitado com `-32600`.
2. Batch com mais de 32 itens: rejeitado com `-32600`.
3. IDs duplicados (excluindo notifications): rejeitado com `-32600`.
4. Cada item deve ser um objeto JSON-RPC 2.0 valido.

### Atomicidade

- Batch **nao** e atomico por padrao. Cada comando e executado independentemente.
- Para atomicidade, use `options.transaction: true` em `sql.executeBatch`.
  Nesse modo, os comandos sao executados na **mesma conexao** e em
  **transacao real de banco** (`begin/commit/rollback`).
- Se um item falha, os demais continuam sendo processados (exceto em modo transacional).

### Exemplo de batch com notification

```json
[
  {
    "jsonrpc": "2.0",
    "method": "sql.execute",
    "id": "q1",
    "params": { "sql": "SELECT 1" }
  },
  {
    "jsonrpc": "2.0",
    "method": "sql.execute",
    "params": { "sql": "INSERT INTO logs (msg) VALUES ('ok')" }
  },
  {
    "jsonrpc": "2.0",
    "method": "sql.execute",
    "id": "q2",
    "params": { "sql": "SELECT 2" }
  }
]
```

Response (notification nao gera item):

```json
[
  {
    "jsonrpc": "2.0",
    "id": "q1",
    "result": { "rows": [{ "1": 1 }], "row_count": 1 }
  },
  {
    "jsonrpc": "2.0",
    "id": "q2",
    "result": { "rows": [{ "2": 2 }], "row_count": 1 }
  }
]
```

## `api_version` e `meta` (contrato formal)

### Definicao

| Campo              | Tipo              | Obrigatorio    | Descricao                         |
| ------------------ | ----------------- | -------------- | --------------------------------- |
| `api_version`      | string            | sim (v2.1+)    | Versao do contrato (ex.: `"2.1"`) |
| `meta.trace_id`    | string            | recomendado    | ID de rastreamento distribuido    |
| `meta.traceparent` | string            | recomendado    | W3C Trace Context principal       |
| `meta.tracestate`  | string            | opcional       | W3C Trace Context vendor-specific |
| `meta.request_id`  | string            | recomendado    | ID unico do request (correlacao)  |
| `meta.agent_id`    | string            | sim (response) | Identificador do agente           |
| `meta.timestamp`   | string (ISO-8601) | sim            | Instante UTC do envio             |

### Politica de obrigatoriedade

- Quando `enableSocketApiVersionMeta` esta ativo, `api_version` e `meta`
  sao **incluidos automaticamente** pelo agente em toda response.
- Requests do hub **devem** incluir `api_version` e `meta` para rastreabilidade.
- Se o hub envia request sem `api_version`, o agente aceita e trata como v2.0 implicito.
- Responses sempre incluem `api_version` e `meta` quando a feature flag esta ativa.
- `traceparent`/`tracestate` sao o formato recomendado para rastreamento
  distribuido; `trace_id` permanece como compatibilidade legada.

### Exemplo completo (request + response)

Request:

```json
{
  "jsonrpc": "2.0",
  "method": "sql.execute",
  "id": "req-456",
  "params": { "sql": "SELECT 1", "client_token": "abc123" },
  "api_version": "2.1",
  "meta": {
    "trace_id": "trace-7f3a",
    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    "tracestate": "vendor=value",
    "request_id": "req-456",
    "agent_id": "agent-01",
    "timestamp": "2026-03-13T10:00:00Z"
  }
}
```

Response:

```json
{
  "jsonrpc": "2.0",
  "id": "req-456",
  "result": { "rows": [{ "1": 1 }], "row_count": 1 },
  "api_version": "2.1",
  "meta": {
    "agent_id": "agent-01",
    "request_id": "req-456",
    "timestamp": "2026-03-13T10:00:01Z"
  }
}
```

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
    "client_token": "a1b2c3d4e5f6...",
    "options": {
      "timeout_ms": 30000,
      "max_rows": 50000,
      "page": 1,
      "page_size": 100
    }
  }
}
```

- `client_token` (ou `clientToken` ou `auth`): obrigatorio quando `enableClientTokenAuthorization`
  esta ativo. Token opaco (hex) criado no agente ou JWT para fallback externo.
- `options.page` e `options.page_size`: habilitam paginacao server-side para
  `SELECT`/`WITH`. Ambos devem ser enviados juntos, `page_size` deve respeitar
  o limite negociado de `max_rows` e a query precisa declarar `ORDER BY`
  explicito.
- **Dialeto da SQL gerada (paginacao gerenciada):** o agente reescreve a query
  conforme o driver configurado — **PostgreSQL** usa `LIMIT`/`OFFSET` no
  envelope; **SQL Server** usa `OFFSET ... ROWS FETCH NEXT ... ROWS ONLY`;
  **SQL Anywhere** usa `TOP n START AT m` (nao suporta `OFFSET`/`FETCH` do
  SQL Server). Integradores (ex.: plug_server) devem enviar apenas `sql` +
  `options`; nao dependem da forma literal da SQL final.
- `options.execution_mode`: controla como o agente trata a SQL. `managed`
  (default) permite reescrita gerenciada para paginacao quando aplicavel.
  `preserve` executa a SQL exatamente como foi enviada e nao aplica reescrita
  gerenciada para paginacao. Nao pode ser combinado com `page`, `page_size`
  ou `cursor`.
- `options.preserve_sql`: alias legado para `execution_mode: "preserve"`.
- `options.multi_result`: habilita retorno explicito de multiplos result sets
  e row counts em `result.result_sets` e `result.items`. Nao pode ser combinado
  com paginacao nem com `params` nomeados.
- `params.database`: override opcional do banco alvo para a request atual.
- `idempotency_key`: reutilizacao da mesma chave com payload diferente e
  rejeitada com `invalid_params`.
- Cache de idempotencia e em memoria e limitado (LRU, 1000 entradas maximas)
  para evitar crescimento sem limite.
- Requests paginadas seguem o caminho request/response tradicional; nao usam
  streaming direto do banco mesmo quando `enableSocketStreamingFromDb` estiver ativo.
- `options.cursor`: token opaco de continuacao retornado em
  `result.pagination.next_cursor`. Quando presente, nao deve ser combinado com
  `page` ou `page_size`, e carrega fingerprint da query + chave(s) do
  `ORDER BY` para continuacao keyset.

Exemplo de continuacao por cursor:

```json
{
  "jsonrpc": "2.0",
  "method": "sql.execute",
  "id": "req-124",
  "params": {
    "sql": "SELECT * FROM users ORDER BY id",
    "options": {
      "cursor": "eyJ2IjoyLCJwYWdlIjoyLCJwYWdlX3NpemUiOjEwMCwicXVlcnlfaGFzaCI6Ii4uLiIsIm9yZGVyX2J5IjpbeyJleHByZXNzaW9uIjoiaWQiLCJsb29rdXBfa2V5IjoiaWQiLCJkZXNjZW5kaW5nIjpmYWxzZX1dLCJsYXN0X3Jvd192YWx1ZXMiOlsxMDBdfQ"
    }
  }
}
```

Exemplo de passthrough sem reescrita:

```json
{
  "jsonrpc": "2.0",
  "method": "sql.execute",
  "id": "req-125",
  "params": {
    "sql": "SELECT * FROM users LIMIT 10",
    "options": {
      "execution_mode": "preserve"
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
    "sql_handling_mode": "managed",
    "max_rows_handling": "response_truncation",
    "rows": [],
    "row_count": 0,
    "affected_rows": 0,
    "column_metadata": [],
    "multi_result": true,
    "result_set_count": 2,
    "item_count": 3,
    "result_sets": [
      {
        "index": 0,
        "rows": [{ "id": 1, "name": "Alice" }],
        "row_count": 1,
        "column_metadata": [{ "name": "id" }, { "name": "name" }]
      },
      {
        "index": 1,
        "rows": [{ "orders_count": 2 }],
        "row_count": 1,
        "column_metadata": [{ "name": "orders_count" }]
      }
    ],
    "items": [
      {
        "type": "result_set",
        "index": 0,
        "result_set_index": 0,
        "rows": [{ "id": 1, "name": "Alice" }],
        "row_count": 1
      },
      {
        "type": "row_count",
        "index": 1,
        "affected_rows": 1
      },
      {
        "type": "result_set",
        "index": 2,
        "result_set_index": 1,
        "rows": [{ "orders_count": 2 }],
        "row_count": 1
      }
    ],
    "pagination": {
      "page": 1,
      "page_size": 100,
      "returned_rows": 0,
      "has_next_page": false,
      "has_previous_page": false
    }
  }
}
```

- `pagination` e retornado apenas quando a request inclui
  `options.page` + `options.page_size` ou `options.cursor`.
- Requests com `options.execution_mode: "preserve"` nao recebem
  `result.pagination`, porque o agente nao gerencia a SQL nem o
  cursor/paginacao do comando.
- `result.sql_handling_mode` expone o modo efetivamente usado (`managed` ou
  `preserve`).
- `result.max_rows_handling` informa a politica ativa para `max_rows`.
  No estado atual, o valor e `response_truncation`.
- `result.effective_max_rows` expoe o limite efetivo de linhas aplicado apos a
  negociacao (min entre o solicitado e o limite do transporte). Facilita debug
  e suporte.
- `result_sets` e `items` aparecem apenas quando a execucao retorna multiplos
  result sets ou row counts no mesmo comando.
- `current_cursor` e `next_cursor` podem aparecer quando o fluxo de
  continuacao por cursor estiver em uso.
- `next_cursor` e gerado a partir da ultima linha retornada e pressupoe
  `ORDER BY` deterministico; para resultados estaveis, a ordenacao deve ser
  unica no conjunto consultado.

### Response de erro

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "error": {
    "code": -32102,
    "message": "SQL execution failed",
    "data": {
      "reason": "sql_execution_failed",
      "category": "sql",
      "retryable": false,
      "user_message": "Nao foi possivel executar a consulta.",
      "technical_message": "Database driver returned an execution error.",
      "correlation_id": "corr-req-123",
      "timestamp": "2026-03-12T10:00:01Z"
    }
  }
}
```

Com extensao v2.1 (quando `enableSocketApiVersionMeta` ativo):

```json
{
  "jsonrpc": "2.0",
  "id": "req-123",
  "error": {
    "code": -32102,
    "message": "SQL execution failed",
    "data": {
      "reason": "sql_execution_failed",
      "category": "sql",
      "retryable": false,
      "user_message": "Nao foi possivel executar a consulta.",
      "technical_message": "Database driver returned an execution error.",
      "correlation_id": "corr-req-123",
      "timestamp": "2026-03-12T10:00:01Z"
    }
  },
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
      { "sql": "SELECT * FROM users", "execution_order": 2 },
      { "sql": "SELECT COUNT(*) AS total FROM orders", "execution_order": 1 }
    ],
    "client_token": "a1b2c3d4e5f6...",
    "options": {
      "timeout_ms": 30000,
      "max_rows": 50000,
      "transaction": false
    }
  }
}
```

- `client_token` (ou `clientToken` ou `auth`): obrigatorio quando `enableClientTokenAuthorization`
  esta ativo.
- `commands[*].execution_order` e opcional (inteiro `>= 0`).
- Quando `execution_order` nao e enviado, o comando segue a ordem da lista
  recebida (comportamento atual).
- Quando o batch mistura comandos com e sem `execution_order`, os comandos com
  `execution_order` sao executados primeiro (ordem crescente), e os sem ordem
  explicita sao executados depois, mantendo a ordem original da lista.
- Quando ha empate de `execution_order`, o desempate usa a ordem original da
  lista.
- `result.items[*].index` continua representando o indice original do comando
  no array `commands`.
- `params.database`: override opcional do banco alvo para o batch atual.
- `idempotency_key`: reutilizacao da mesma chave com payload diferente e
  rejeitada com `invalid_params`.
- Cache de idempotencia e em memoria e limitado (LRU, 1000 entradas maximas)
  para evitar crescimento sem limite.

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

| Codigo   | Cenario comum                                             | Acao recomendada no cliente                            |
| -------- | --------------------------------------------------------- | ------------------------------------------------------ |
| `-32700` | JSON malformado                                           | corrigir serializacao JSON e reenviar                  |
| `-32600` | request invalida                                          | validar contrato antes de enviar                       |
| `-32601` | metodo inexistente                                        | ajustar nome do metodo para um suportado               |
| `-32602` | parametros invalidos                                      | corrigir payload antes de reenviar                     |
| `-32603` | erro interno                                              | retry com backoff; se persistir, acionar suporte       |
| `-32001` | falha de autenticacao ou token ausente                    | incluir `client_token` em params ou renovar credencial |
| `-32002` | sem permissao (token revogado, nao encontrado, ou negado) | ocultar acao na UI e orientar contato com admin        |
| `-32008` | timeout                                                   | retry com backoff e observabilidade                    |
| `-32009` | payload invalido                                          | validar schema e encoding antes do envio               |
| `-32010` | falha de decode                                           | verificar content-type/encoding e compatibilidade      |
| `-32011` | falha de compressao                                       | reenviar sem compressao (fallback) e registrar erro    |
| `-32012` | erro de rede                                              | reconectar socket e repetir com controle               |
| `-32013` | limite de requests por janela excedido                    | aplicar backoff e reduzir concorrencia                 |
| `-32014` | request duplicada (replay)                                | reenviar com novo `id`/correlation                     |

### Formato de erro

O objeto `error.data` segue um formato estruturado para UX e troubleshooting:

- `reason`: identificador estavel do motivo do erro
- `category`: classe do erro para automacao e roteamento
- `retryable`: indica se retry automatico faz sentido
- `user_message`: mensagem amigavel para exibicao
- `technical_message`: detalhe tecnico para logs e suporte
- `correlation_id`: identificador para correlacionar logs
- `timestamp`: instante UTC da falha

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
      "category": "sql",
      "retryable": false,
      "user_message": "Execucao nao encontrada. Pode ter sido finalizada ou nunca iniciada.",
      "technical_message": "No in-flight execution found to cancel.",
      "correlation_id": "corr-cancel-req-1",
      "timestamp": "2026-03-12T10:00:03Z"
    }
  }
}
```

**Nota**: O cancelamento aplica-se apenas a execucoes em streaming (ex.: Playground).
Execucoes via `sql.execute` (nao-streaming) nao sao cancelaveis por este metodo.

## Contrato obrigatorio de erro (`error.data`)

Para padronizar UX e troubleshooting, toda resposta de erro deve incluir:

- `reason`: motivo estruturado do erro (enum estavel para automacao)
- `category`: classe do erro (`validation`, `auth`, `network`, `transport`, `sql`, `database`, `internal`)
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

| Valor        | Uso                                    |
| ------------ | -------------------------------------- |
| `validation` | erro de contrato, parametro ou formato |
| `auth`       | autenticacao, autorizacao ou token     |
| `network`    | conectividade, socket, handshake       |
| `transport`  | payload, encoding, compressao, framing |
| `sql`        | validacao ou execucao SQL              |
| `database`   | conectividade/configuracao do banco    |
| `internal`   | falha interna nao categorizada         |

### `reason`

| Codigo   | `reason` recomendado                                     |
| -------- | -------------------------------------------------------- |
| `-32700` | `json_parse_error`                                       |
| `-32600` | `invalid_request`                                        |
| `-32601` | `method_not_found`                                       |
| `-32602` | `invalid_params`                                         |
| `-32603` | `internal_error`                                         |
| `-32001` | `authentication_failed` ou `missing_client_token`        |
| `-32002` | `unauthorized` (ex.: `token_revoked`, `token_not_found`) |
| `-32008` | `timeout`                                                |
| `-32009` | `invalid_payload`                                        |
| `-32010` | `decoding_failed`                                        |
| `-32011` | `compression_failed`                                     |
| `-32012` | `network_error`                                          |
| `-32013` | `rate_limited`                                           |
| `-32014` | `replay_detected`                                        |
| `-32101` | `sql_validation_failed`                                  |
| `-32102` | `sql_execution_failed`                                   |
| `-32103` | `transaction_failed`                                     |
| `-32104` | `connection_pool_exhausted`                              |
| `-32105` | `result_too_large`                                       |
| `-32106` | `database_connection_failed`                             |
| `-32107` | `query_timeout`                                          |
| `-32108` | `invalid_database_config`                                |

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

| Parametro              | Valor padrao              | Descricao                          |
| ---------------------- | ------------------------- | ---------------------------------- |
| `rateLimitWindow`      | 1 minuto                  | Janela deslizante para contagem    |
| `maxRequestsPerWindow` | 120                       | Maximo de `rpc:request` por janela |
| Codigo de erro         | `-32013` (`rate_limited`) | HTTP 429                           |

### Replay protection

| Parametro      | Valor padrao                 | Descricao                          |
| -------------- | ---------------------------- | ---------------------------------- |
| `replayWindow` | 2 minutos                    | Janela de validade de `request.id` |
| Codigo de erro | `-32014` (`replay_detected`) | HTTP 409                           |

### Codigos de erro finais (transport)

| Codigo   | `reason`          | `category` | `retryable` |
| -------- | ----------------- | ---------- | ----------- |
| `-32013` | `rate_limited`    | transport  | false       |
| `-32014` | `replay_detected` | transport  | false       |

## Compatibilidade de erro

O contrato ativo do transporte e `rpc:response`. Clientes devem tratar
erros exclusivamente pelo envelope JSON-RPC v2.

## Idioma e localizacao de erros

- `message`, `reason`, `technical_message`: manter em ingles estavel
  (orientado a contrato e logs).
- `user_message`: texto amigavel localizavel (pt-BR na UI atual).
- Evitar mistura de idiomas no mesmo campo.

## Capabilities (negociacao atual)

Exemplo de capacidades anunciadas:

```json
{
  "protocols": ["jsonrpc-v2"],
  "encodings": ["json"],
  "compressions": ["gzip", "none"],
  "extensions": {
    "batchSupport": true,
    "binaryPayload": true,
    "streamingResults": false,
    "plugProfile": "plug-jsonrpc-profile/2.5",
    "orderedBatchResponses": true,
    "notificationNullIdCompatibility": true,
    "paginationModes": ["page-offset", "cursor-keyset"],
    "traceContext": ["w3c-trace-context", "legacy-trace-id"],
    "errorFormat": "structured-error-data"
  }
}
```

## Compatibilidade e Fallback

- O agente transmite eventos de aplicacao como `PayloadFrame` binario quando
  `enableBinaryPayload` estiver ativo.
- O agente ainda aceita payload logico JSON cru no recebimento como
  compatibilidade temporaria de rollout/homologacao.
- Eventos legados fora do contrato v2 continuam fora do escopo deste
  documento.

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
    {
      "query": "SELECT * FROM users",
      "parameters": {},
      "client_token": "a1b2c3d4e5f6..."
    }
  ]
}
```

- `client_token` (ou `auth`) no payload: obrigatorio quando auth ativo.

## Client Token Authorization (implementado)

### Fluxo

1. Cliente envia token em `params.client_token` ou `params.clientToken` ou `params.auth`.
2. Agente normaliza (aceita `Bearer <token>` ou token direto).
3. Lookup local: hash SHA-256 do token -> SQLite -> politica (regras, all_tables, all_views, all_permissions).
4. Se nao encontrado localmente: fallback opcional para JWKS (JWT) quando `enableSocketJwksValidation` ativo.
5. Politica define se a operacao SQL e permitida; deny tem precedencia sobre allow.

### Formato do token

- **Tokens criados no agente**: opacos (string hex aleatoria). Permissoes ficam no banco local, nao no token.
- **Fallback externo**: JWT com payload `policy` quando JWKS ativo.

### Onde passar o token

| Protocolo          | Local                                                          |
| ------------------ | -------------------------------------------------------------- |
| v2 (`rpc:request`) | `params.client_token` ou `params.clientToken` ou `params.auth` |

### Feature flag

- `enableClientTokenAuthorization`: default **true**. Quando ativo, token vazio ou ausente retorna `-32001` (authentication failed) ou `-32002` (unauthorized).

## Observabilidade de autorizacao (implementado)

- Coleta de metricas de autorizacao em memoria (allow/deny, por operacao, recurso e motivo).
- Logs estruturados no transporte para decisoes de autorizacao no fluxo RPC (`authorization.allowed` e `authorization.denied`).
- Exibicao de resumo de autorizacao no dashboard via `WebSocketLogViewer`.
- Quando o RPC retorna `authentication_failed` ou `token_revoked`, o transporte
  dispara callback de refresh de token/reconexao.
- Contadores operacionais em memoria para observabilidade de resiliencia:
  `timeout_cancel_success`, `timeout_cancel_failure`,
  `transaction_rollback_failure` e `idempotency_fingerprint_mismatch`.

## Politica de versao e deprecacao

### Versionamento

| Versao | Descricao                                                      | Status |
| ------ | -------------------------------------------------------------- | ------ |
| `2.0`  | JSON-RPC 2.0 base (sql.execute, sql.executeBatch, erros)       | stable |
| `2.1`  | Extensoes: api_version, meta, client_token auth, notifications | stable |
| `2.2`  | Hardening de limites negociados e assinatura de payload        | stable |
| `2.3`  | Profile formal, OpenRPC, observabilidade e cursor opaco        | stable |
| `2.4`  | Cursor keyset, output validation e `rpc.discover`              | stable |
| `2.5`  | execution_mode preserve, alias legado e metadata de handling   | stable |

### Regras de versionamento

- **Semver no contrato**: versoes `major.minor`. Major = breaking change; minor = extensao compativel.
- **`api_version`** no payload indica a versao do contrato que o emissor espera.
- Se o agente recebe uma `api_version` desconhecida, processa como a versao mais recente suportada e inclui sua propria `api_version` na response.
- Novas features sao introduzidas como **extensoes opcionais** (feature flags) e promovidas a default apos validacao.

### Deprecacao

- Uma versao e marcada como `deprecated` quando sua substituicao esta estavel.
- Periodo de deprecacao minimo: **90 dias** apos anuncio.
- Apos o periodo, a versao deprecated pode ser removida em uma release futura.
- O agente emite log `WARN` quando recebe requests em versao deprecated.

### Ciclo de vida de feature flag

1. **Experimental**: flag desativado por default; funcionalidade disponivel para opt-in.
2. **Stable**: flag ativado por default; funcionalidade validada com clientes.
3. **Mandatory**: flag removido; funcionalidade sempre ativa.
4. **Deprecated flag**: flag ignorado; funcionalidade revertida ou absorvida.

## Limites negociados por transporte

### Limites do agente (defaults atuais)

| Parametro                 | Valor padrao | Descricao                                                                 |
| ------------------------- | ------------ | ------------------------------------------------------------------------- |
| `max_payload_bytes`       | 10 MB        | Tamanho maximo de um unico payload (request ou response)                  |
| `max_rows`                | 50.000       | Maximo de linhas retornadas por `sql.execute` (sem streaming)             |
| `max_batch_size`          | 32           | Maximo de comandos em `sql.executeBatch`                                  |
| `max_concurrent_streams`  | 1            | Maximo de streams de resultado ativos simultaneamente                     |
| `streaming_chunk_size`    | 500          | Linhas por chunk em streaming                                             |
| `streaming_row_threshold` | 500          | Acima deste limite negociado, resultado pode ser streamed automaticamente |

### Negociacao (implementado)

O agente anuncia limites em `agent:register` via campo `limits` dentro de `capabilities`:

```json
{
  "protocols": ["jsonrpc-v2"],
  "encodings": ["json"],
  "compressions": ["gzip", "none"],
  "extensions": { "batchSupport": true },
  "limits": {
    "max_payload_bytes": 10485760,
    "max_rows": 50000,
    "max_batch_size": 32,
    "max_concurrent_streams": 1
  }
}
```

- O hub responde com `agent:capabilities` incluindo limites ajustados.
- O valor efetivo e o **minimo** entre o que o agente e o hub suportam (`TransportLimits.negotiateWith`).
- Os limites efetivos ficam armazenados em `ProtocolConfig.effectiveLimits`.

### Enforcement

- Request que excede `max_payload_bytes`: rejeitado com `-32009` (invalid payload).
- Response que excede `max_rows`: truncado ou streamed (conforme feature flags).
- Batch que excede `max_batch_size`: rejeitado com `-32600` (invalid request).

## Assinatura opcional de transporte/payload

### Objetivo

Garantir integridade e autenticidade de payloads em transito entre hub e agente.

### Mecanismo (implementado)

Quando ativo, o emissor inclui `signature` no `PayloadFrame`:

```json
{
  "schemaVersion": "1.0",
  "enc": "json",
  "cmp": "gzip",
  "contentType": "application/json",
  "originalSize": 1200,
  "compressedSize": 340,
  "payload": "<binary>",
  "traceId": "trace-123",
  "requestId": "req-123",
  "signature": {
    "alg": "hmac-sha256",
    "value": "base64-encoded-hmac",
    "key_id": "shared-key-01"
  }
}
```

### Campos

| Campo              | Tipo   | Descricao                       |
| ------------------ | ------ | ------------------------------- |
| `signature.alg`    | string | Algoritmo (ex.: `hmac-sha256`)  |
| `signature.value`  | string | Assinatura codificada em base64 |
| `signature.key_id` | string | Identificador da chave usada    |

### Regras

- **Opcional**: o emissor pode omitir `signature`; o receptor aceita sem verificar.
- **Verificacao**: quando presente, o receptor **deve** verificar. Se invalida, retorna `-32001` (authentication failed) com `reason: invalid_signature`.
- **Escopo principal**: a assinatura cobre `schemaVersion`, `enc`, `cmp`,
  `contentType`, tamanhos, `traceId`, `requestId` e os bytes do `payload`.
- **Compatibilidade**: quando o modo binario estiver desativado por feature
  flag, a assinatura legada sobre o payload logico JSON continua sendo aceita.
- **Algoritmos suportados**: `hmac-sha256` (inicial). Extensivel para `ed25519` no futuro.
- **Key management**: chaves compartilhadas configuradas no agente via settings. Rotacao por `key_id`.

### Feature flag

- `enablePayloadSigning`: quando ativo, o agente verifica assinaturas em requests recebidos e assina responses enviados.

### Implementacao

- Classe `PayloadSigner` em `infrastructure/security/payload_signer.dart`.
- Chaves configuradas via `.env` (`PAYLOAD_SIGNING_KEY`, `PAYLOAD_SIGNING_KEY_ID`).
- Integrado ao `SocketIOTransportClientV2`: assina frames enviados e verifica
  frames recebidos.
- Comparacao constant-time para prevenir timing attacks.
- Feature flag `enablePayloadSigning` (default `false`).

## Limites operacionais atuais

- `options.timeout_ms` suportado em `sql.execute` e `sql.executeBatch`.
- `options.max_rows` suportado em `sql.execute` e `sql.executeBatch`.
- `options.page` e `options.page_size` suportados em `sql.execute`.
- `options.cursor` suportado em `sql.execute`.
- `options.execution_mode` suportado em `sql.execute`.
- `options.preserve_sql` suportado em `sql.execute` como alias legado.
- `sql.executeBatch` **nao** suporta `execution_mode`; todos os comandos rodam em
  modo managed implicito. Politica futura: evoluir em versao posterior (ex.:
  `options.execution_mode` no batch ou `commands[*].execution_mode` por comando).
- `options.multi_result` suportado em `sql.execute`.
- `commands[*].execution_order` suportado em `sql.executeBatch`.
- `result.pagination` retornado apenas para requests paginadas.
- `result.result_sets` e `result.items` retornados apenas para execucoes
  multi-result.
- Para fluxos sem streaming, payload segue request/response unico.
- Requests paginadas nao usam o modo de streaming direto do banco.
- `options.execution_mode: "preserve"` mantem a SQL original; limites, auth,
  schema e tratamento de erro continuam sendo aplicados normalmente.
- `max_rows` continua sendo aplicado como truncamento da response
  (`response_truncation`). O agente nao reescreve a SQL para empurrar esse
  limite ao banco quando `execution_mode` e `preserve`.
- Limites de transporte documentados na secao "Limites negociados" acima.

## Limitacoes e observacoes do estado atual

- O transporte ativo usa `PayloadFrame` binario como camada fisica padrao.
- A leitura de payload logico JSON cru ainda existe apenas como compatibilidade
  temporaria para rollout.
- A compressao e decidida por threshold; clientes devem aceitar `cmp: gzip` e
  `cmp: none`.
- Nao existe metodo RPC generico de transferencia de arquivo no contrato atual;
  qualquer conteudo de arquivo precisa ser modelado no payload logico do metodo
  e, depois, transportado dentro do `PayloadFrame`.
- Metodo `sql.cancel` disponivel via feature flag `enableSocketCancelMethod`
  (cancela execucao em streaming ativa; execucoes nao-streaming nao sao
  cancelaveis).
- Streaming chunked: ativo via `enableSocketStreamingChunks`; resultados
  acima de `streaming_row_threshold` negociado sao enviados em chunks
  (`rpc:chunk`, `rpc:complete`).
- Backpressure: implementado quando `enableSocketBackpressure`; o hub envia
  `rpc:stream.pull` com `window_size` para controlar quantos chunks o agente
  envia por vez; credito inicial de 1 chunk.
- `api_version`/`meta` disponiveis via feature flag `enableSocketApiVersionMeta`;
  contrato formal na secao "api_version e meta".
- Notification JSON-RPC (sem `id`) formalizada na secao "Notification JSON-RPC";
  enforcement via `enableSocketNotificationsContract`.
- Regras estritas de batch formalizadas na secao "Regras formais de batch";
  enforcement via `enableSocketBatchStrictValidation`.
- Timeout por etapa (SQL, transporte, ack) disponivel via
  `enableSocketTimeoutByStage`; erros incluem `reason` especifico
  (`query_timeout`, `transport_timeout`, `ack_timeout`).
- Em timeout de SQL, o agente aplica cancelamento best-effort da execucao no
  banco (desconexao/recuperacao de conexao) para evitar trabalho zumbi.
- Garantia de entrega por tipo de evento disponivel via
  `enableSocketDeliveryGuarantees`; ver tabela abaixo quando ativo.
- Connection state recovery com retry/backoff esta ativo agent-side.
- Politica de refresh/auth no reconnect esta ativa agent-side.
- Rate limits/quotas por evento estao ativos agent-side.
- Schemas JSON publicados em `docs/communication/schemas/`. Validacao automatica
  na entrada disponivel via `enableSocketSchemaValidation`.
- OpenRPC publicado em `docs/communication/openrpc.json` para descoberta do
  profile RPC.
- Autorizacao por client token: lookup local por hash SHA-256 (tokens opacos criados no agente).
  Permissoes armazenadas em SQLite local; token usado apenas para validacao e lookup.
- Validacao criptografica de token (issuer/audience/kid/alg) disponivel via
  `enableSocketJwksValidation` como fallback para JWT externos; JWKS URL derivado de
  `serverUrl/.well-known/jwks.json` ou override por `JWKS_URL` (env). Opcional: `JWKS_ISSUER`, `JWKS_AUDIENCE`.
- Revogacao de token com efeito em sessao ativa disponivel via
  `enableSocketRevokedTokenInSession`; tokens revogados sao armazenados em
  memoria com TTL e rejeitados em novas requests sem exigir reconexao.
- Trilha de auditoria para token management (create/revoke/revoked_in_session)
  disponivel via `enableTokenAudit`; persistencia em JSONL.

## Checklist de homologacao do cliente

### Fluxo basico

- [ ] Executa fluxo v2 completo (`agent:register` -> `rpc:request` -> `rpc:response`) usando `PayloadFrame`.
- [ ] Homologa encode/compress/decode/decompress no cliente.
- [ ] Trata erro JSON-RPC em vez de assumir sempre `result`.
- [ ] Homologa `sql.execute` com sucesso e com falha SQL.
- [ ] Homologa `sql.executeBatch` com itens de retorno.
- [ ] Valida fallback para protocolo legado quando v2 nao estiver disponivel.

### Erros e retry

- [ ] Homologa erros de payload invalido (`-32009`) e decode (`-32010`).
- [ ] Homologa falha de frame/signature/descompressao (`-32011` e `invalid_signature`).
- [ ] Homologa falha de auth (`-32001`) e permissao (`-32002`).
- [ ] Valida regra de retry somente quando `retryable=true`.
- [ ] Exibe `user_message` ao usuario e registra `correlation_id` para suporte.
- [ ] Garante equivalencia de comportamento entre legado e v2 para mesmos cenarios.

### Autorizacao

- [ ] Envia `client_token` em `params` para toda request quando auth ativo.
- [ ] Trata `-32001` (missing/invalid token) e `-32002` (unauthorized).
- [ ] Valida que token revogado retorna `-32002` com `reason: token_revoked`.

### Contrato v2.1

- [ ] Inclui `api_version` e `meta` em requests (quando feature ativa).
- [ ] Valida que responses incluem `api_version` e `meta`.
- [ ] Trata notifications (request sem `id`) sem esperar response.
- [ ] Respeita limite de 32 itens por batch com IDs unicos.
- [ ] Valida schemas de params conforme schemas publicados.

## Changelog do protocolo (implementado)

### `v2.0`

- Introducao de JSON-RPC 2.0 no transporte Socket.IO.
- Inclusao de `sql.execute` e `sql.executeBatch`.
- Catalogo de erros padronizado e mapeamento de failures.
- Negociacao de capacidades no handshake.

### `v2.1` (auth + contratos formais)

- Client token authorization com tokens opacos (hash SHA-256 em SQLite local).
- Permissoes armazenadas no banco; token usado apenas para lookup.
- `params.client_token` (ou `clientToken`, `auth`) obrigatorio quando auth ativo.
- Contrato formal de notifications JSON-RPC (request sem `id`, sem response).
- Contrato formal de batch (IDs unicos, max 32, ordenacao, atomicidade).
- `api_version` + `meta` formalizados como contrato obrigatorio.
- Schemas JSON de params por metodo (`sql.execute`, `sql.executeBatch`, `sql.cancel`).
- Schemas JSON de streaming (`rpc:chunk`, `rpc:complete`, `rpc:stream.pull`).
- Politica de versao e deprecacao publicada.
- Limites de transporte documentados (defaults fixos).
- Assinatura de payload especificada.

### `v2.2` (hardening)

- Negociacao real de limites via `TransportLimits` no handshake (`agent:register` / `agent:capabilities`).
- Assinatura de payload implementada (`PayloadSigner`, HMAC-SHA256, constant-time verify).
- Feature flag `enablePayloadSigning` adicionada (default `false`).
- Feature flags promovidas para default `true`: `enableClientTokenAuthorization`, `enableSocketApiVersionMeta`, `enableSocketNotificationsContract`, `enableSocketBatchStrictValidation`, `enableSocketSchemaValidation`, `enableSocketCancelMethod`.

### `v2.3` (profile + observabilidade + paginacao cursor)

- Plug JSON-RPC Profile formalizado sobre JSON-RPC 2.0.
- `traceparent` e `tracestate` adicionados ao contrato de `meta`.
- OpenRPC publicado para descoberta do contrato.
- Schemas especificos de result por metodo (`sql.execute`, `sql.executeBatch`).
- Paginacao por cursor opaco adicionada a `sql.execute`.
- Semantica de erro estruturado formalizada em `error.data`.

### `v2.4` (cursor keyset + output validation + discover)

- Paginacao exige `ORDER BY` explicito para requests paginadas.
- `options.cursor` passa a representar continuacao keyset com fingerprint da query.
- `notificationNullIdCompatibility` passa a governar `id: null` em runtime.
- Respostas `rpc:response`, `rpc:chunk`, `rpc:complete` e payloads de handshake
  sao validados antes do envio quando `enableSocketSchemaValidation` esta ativo.
- `rpc.discover` retorna o documento OpenRPC publicado.
- Todos os eventos de aplicacao passam a trafegar em `PayloadFrame` binario.
- Compressao GZIP foi movida para a borda de transporte com fallback `cmp: none`
  por threshold.
- Assinatura passa a cobrir o frame de transporte quando o modo binario esta
  ativo.
- `sql.executeBatch` aceita `commands[*].execution_order` opcional, com
  fallback para ordem da lista quando ausente.

### `v2.5` (sql handling mode + passthrough explicito)

- `options.execution_mode` adicionado a `sql.execute` com valores `managed`
  (default) e `preserve`.
- `options.preserve_sql` mantido como alias legado para
  `execution_mode: "preserve"`.
- Responses de `sql.execute` passam a incluir `sql_handling_mode`.
- Responses de `sql.execute` passam a incluir `max_rows_handling`.
- `execution_mode: "preserve"` nao pode ser combinado com `page`,
  `page_size` ou `cursor`.
- `max_rows` em modo `preserve` permanece como truncamento da response, sem
  reescrita da SQL enviada pelo cliente.

## Schemas JSON (contrato)

### Envelope

- `docs/communication/schemas/rpc.request.schema.json`
- `docs/communication/schemas/rpc.response.schema.json`
- `docs/communication/schemas/rpc.error.schema.json`
- `docs/communication/schemas/rpc.batch.request.schema.json`
- `docs/communication/schemas/rpc.batch.response.schema.json`
- `docs/communication/schemas/agent.register.schema.json`
- `docs/communication/schemas/agent.capabilities.schema.json`

### Params por metodo

- `docs/communication/schemas/rpc.params.sql-execute.schema.json`
- `docs/communication/schemas/rpc.params.sql-execute-batch.schema.json`
- `docs/communication/schemas/rpc.params.sql-cancel.schema.json`

### Result por metodo

- `docs/communication/schemas/rpc.result.sql-execute.schema.json`
- `docs/communication/schemas/rpc.result.sql-execute-batch.schema.json`

### Streaming

- `docs/communication/schemas/rpc.stream.chunk.schema.json`
- `docs/communication/schemas/rpc.stream.complete.schema.json`
- `docs/communication/schemas/rpc.stream.pull.schema.json`

### OpenRPC

- `docs/communication/openrpc.json`

## Referencias internas

- Modelos RPC: `lib/domain/protocol/`
- Dispatcher RPC: `lib/application/rpc/rpc_method_dispatcher.dart`
- Transporte: `lib/infrastructure/external_services/socket_io_transport_client_v2.dart`
- Negociacao: `lib/application/services/protocol_negotiator.dart`
- Guia de cliente: `docs/communication/socketio_client_binary_transport.md`
- Evolucao pendente: `docs/communication/socket_communication_roadmap.md`
