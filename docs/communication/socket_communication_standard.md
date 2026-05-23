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
  - `sql.bulkInsert`
  - `sql.cancel` (feature flag `enableSocketCancelMethod`)
  - `agent.getProfile`
  - `agent.getHealth`
  - `agent.action.run` (feature flag `enableRemoteAgentActions`)
  - `agent.action.validateRun` (feature flag `enableRemoteAgentActions`)
  - `agent.action.cancel` (feature flag `enableRemoteAgentActions`)
  - `agent.action.getExecution` (feature flag `enableRemoteAgentActions`)
  - `client_token.getPolicy`
  - `rpc.discover`
- Catalogo padronizado de erros RPC
- Negociacao de capacidades

## Status de implementacao


| Item                                                                 | Status                                                                                                                     |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| JSON-RPC 2.0 (`rpc:request`/`rpc:response`)                          | implemented                                                                                                                |
| Metodo `sql.execute`                                                 | implemented                                                                                                                |
| Metodo `sql.executeBatch`                                            | implemented                                                                                                                |
| Metodo `sql.bulkInsert`                                              | implemented                                                                                                                |
| Metodo `agent.getProfile`                                            | implemented                                                                                                                |
| Metodo `agent.getHealth`                                             | implemented                                                                                                                |
| Metodo `agent.action.run`                                            | implemented (via feature flag `enableRemoteAgentActions`; enfileira apenas acao salva/aprovada, com idempotencia obrigatoria) |
| Metodo `agent.action.validateRun`                                    | implemented (via feature flag `enableRemoteAgentActions`; preflight remoto sem persistir execucao nem iniciar processo; mesma `idempotency_key` que `run`) |
| Metodo `agent.action.cancel`                                         | implemented (via feature flag `enableRemoteAgentActions`; cancela fila ou mata apenas processo principal)                  |
| Metodo `agent.action.getExecution`                                   | implemented (via feature flag `enableRemoteAgentActions`; leitura redigida de execucao de acao)                            |
| Metodo `client_token.getPolicy`                                      | implemented                                                                                                                |
| Catalogo de erros RPC                                                | implemented                                                                                                                |
| Negociacao de capacidades                                            | implemented                                                                                                                |
| Transporte binario em `PayloadFrame`                                 | implemented (obrigatorio; sem fallback para JSON cru)                                                                      |
| Compressao GZIP na borda de transporte                               | implemented (por threshold; fallback `cmp: none`)                                                                          |
| Compatibilidade de leitura para payload JSON cru                     | not supported in current runtime                                                                                           |
| `sql.cancel`                                                         | implemented (via feature flag)                                                                                             |
| Streaming chunked                                                    | implemented (`enableSocketStreamingChunks`; default **off**; acima de `streaming_row_threshold`)                         |
| Streaming direto do banco (SELECT sem params)                        | implemented (`enableSocketStreamingFromDb`; default **on**)                                                                |
| Backpressure                                                         | implemented (`enableSocketBackpressure`; default **off**; `window_size` em `rpc:stream.pull`)                              |
| Ack explicito de prontidao (`agent:ready`)                           | implemented (agent-side; opcional e retrocompativel)                                                                       |
| Notification JSON-RPC (sem resposta)                                 | implemented (via feature flag); contrato formal                                                                            |
| Regras estritas de batch (IDs unicos/ordem)                          | implemented (via feature flag); contrato formal                                                                            |
| Garantia de entrega por evento (ack/retry)                           | implemented (`enableSocketDeliveryGuarantees`; default **off**)                                                            |
| Timeout por etapa (SQL, transporte, ack)                             | implemented (`enableSocketTimeoutByStage`; default **off**)                                                              |
| Idempotencia por `idempotency_key` (sql.execute/batch/bulkInsert + extensoes) | implemented (`enableSocketIdempotency`; default **off**; cache SQLite com TTL/LRU; chave `{method}:{key}`)        |
| Connection state recovery                                            | implemented (agent-side retry/backoff)                                                                                     |
| Politica de auth no reconnect                                        | implemented (agent-side)                                                                                                   |
| Rate limiting por evento                                             | implemented (agent-side)                                                                                                   |
| Schema JSON oficial de contrato                                      | implemented (envelope + params + streaming)                                                                                |
| Schema de params por metodo (sql.execute/batch/cancel)               | implemented (docs/communication/schemas/)                                                                                  |
| Schema de streaming (chunk/complete/pull)                            | implemented (docs/communication/schemas/)                                                                                  |
| Politica de versao e deprecacao                                      | implemented (neste documento)                                                                                              |
| Limites negociados por transporte                                    | implemented (negociacao via TransportLimits no handshake)                                                                  |
| Assinatura opcional de payload                                       | implemented (HMAC-SHA256; `enablePayloadSigning`; default **off**)                                                         |
| Validacao de schema na entrada (rpc:request)                         | implemented (via feature flag)                                                                                             |
| Validacao de contrato na saida (`rpc:response`, batch, streaming)    | implemented (via `enableSocketOutgoingContractValidation`; acima de ~2 MiB UTF-8 a validacao de saida e omitida por custo) |
| Resumo de payloads grandes no tracer Socket (`onMessage`)            | implemented (via `enableSocketSummarizeLargePayloadLogs`; limiar 8 KiB UTF-8 estimado)                                     |
| Client token authorization (opaco + hash lookup)                     | implemented (default on)                                                                                                   |
| Validacao criptografica de token (JWKS)                              | implemented (via feature flag; fallback)                                                                                   |
| Revogacao em sessao ativa                                            | implemented (via feature flag)                                                                                             |
| Observabilidade de autorizacao (collector allow/deny)                | implemented                                                                                                                |
| Logs de decisao de autorizacao no transporte (`AUTH`)                | implemented                                                                                                                |
| Resumo de autorizacao no dashboard (`WebSocketLogViewer`)            | implemented                                                                                                                |
| Refresh de auth em runtime (`token_revoked`/`authentication_failed`) | implemented                                                                                                                |
| Heartbeat de sessao (`agent:heartbeat`/`hub:heartbeat_ack`)          | implemented (agent-side)                                                                                                   |
| Recovery de conexao curta com retry/backoff                          | implemented (agent-side)                                                                                                   |
| Replay protection por janela de request ID                           | implemented (agent-side)                                                                                                   |
| Auditoria de token management                                        | implemented (via feature flag)                                                                                             |


### Agent defaults

**Implemented** indica codigo e contrato disponiveis no runtime, nao que a
funcionalidade esteja ativa em instalacao padrao. Flags abaixo iniciam
**desligadas** (`FeatureFlags` / preferencias do app): `enableSocketStreamingChunks`,
`enableSocketBackpressure`, `enablePayloadSigning`, `enableSocketIdempotency`,
`enableSocketDeliveryGuarantees`, `enableSocketTimeoutByStage`. Flags de
protocolo maduro (ex.: `enableSocketCancelMethod`, `enableSocketSchemaValidation`,
`enableClientTokenAuthorization`, `enableSocketStreamingFromDb`) iniciam
**ligadas**. Habilite as flags opt-in nas configuracoes do agente quando o hub
exigir o comportamento correspondente.

## Plug JSON-RPC Profile

O transporte usa JSON-RPC 2.0 como base, mas o contrato operacional deste
projeto e o **Plug JSON-RPC Profile**.

Esse profile formaliza extensoes que nao fazem parte do JSON-RPC puro:

- compatibilidade opcional para notification com `id: null`
- batch com validacao estrita e ordenacao estavel de responses
- metadata operacional em `api_version` + `meta`
- payload de erro estruturado em `error.data`
- limites negociados no handshake
- paginacao por `page/page_size` e por `cursor`, sempre exigindo `ORDER BY`
explicito para estabilidade e reescrita gerenciada

As semanticas ativas podem ser anunciadas em `capabilities.extensions` no
handshake.

## Eventos Socket.IO Ativos

### Negociacao

- `agent:register`
  - enviado pelo agente na conexao
  - inclui identificacao, capacidades e `profile` opcional quando o cadastro do agente estiver completo
- `agent:capabilities`
  - recebido do hub para definir protocolo efetivo
- `agent:ready`
  - enviado pelo agente apos concluir a negociacao efetiva do protocolo

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


| Evento                 | Direcao       | Payload esperado                                                        | Resposta                                                                                                                                                   |
| ---------------------- | ------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `agent:register`       | agente -> hub | `PayloadFrame<{ agentId, timestamp, capabilities, profile?, profile_version?, profile_updated_at? }>` | `agent:capabilities` ou `agent:register_error`                                                                                                             |
| `agent:capabilities`   | hub -> agente | `PayloadFrame<{ capabilities }>`                                        | define protocolo efetivo                                                                                                                                   |
| `agent:register_error` | hub -> agente | `{ code, reason, message }` (estrutura JSON, NAO PayloadFrame)          | rejeicao de `agent:register`. `code/reason` `transient_failure` ou `rate_limited` agendam novo registro; demais valores forçam reconexao.                  |
| `agent:ready`          | agente -> hub | `PayloadFrame<{ agent_id, timestamp, protocol }>`                       | sinal opcional de prontidao explicita para hubs que anunciam `extensions.protocolReadyAck`                                                                 |
| `rpc:request`          | hub -> agente | `PayloadFrame<JSON-RPC 2.0 request>`                                    | `rpc:response`                                                                                                                                             |
| `rpc:request_ack`      | agente -> hub | `PayloadFrame<{ request_id, received_at }>`                             | (quando `enableSocketDeliveryGuarantees`)                                                                                                                  |
| `rpc:batch_ack`        | agente -> hub | `PayloadFrame<{ request_ids, received_at }>`                            | (quando `enableSocketDeliveryGuarantees`)                                                                                                                  |
| `rpc:chunk`            | agente -> hub | `PayloadFrame<{ stream_id, request_id, chunk_index, rows }>`            | (quando `enableSocketStreamingChunks`)                                                                                                                     |
| `rpc:complete`         | agente -> hub | `PayloadFrame<{ stream_id, request_id, total_rows, terminal_status? }>` | (quando `enableSocketStreamingChunks`; `terminal_status` opcional `aborted`/`error` quando o stream termina sem sucesso completo — ver texto em streaming) |
| `rpc:stream.pull`      | hub -> agente | `PayloadFrame<{ stream_id, window_size }>`                              | (quando `enableSocketBackpressure`)                                                                                                                        |


**Timeout de capabilities:** Se o hub nao responder com `agent:capabilities` dentro
de `capabilitiesTimeoutMs` (default 8 s) apos `agent:register`, o agente reenvia
`agent:register` em ate `capabilitiesMaxReRegisterAttempts` ciclos extras
(default 2). O total e: 1 registro inicial + 2 re-registros = 3 emissoes maximas
de `agent:register` por handshake antes de o agente forçar reconexao.

**Readiness:** O hub nao deve enviar `rpc:request` antes de o agente ter recebido
`agent:capabilities`. O agente so considera o protocolo pronto apos a negociacao
completa. O `connect` pode retornar sucesso assim que o transporte Socket.IO
estabelece conexao; o agente envia `agent:register`, aguarda
`agent:capabilities` e, em seguida, emite `agent:ready` como ack explicito
retrocompativel para hubs que anunciam `extensions.protocolReadyAck`. Se o hub
enviar RPC antes disso, o agente rejeita a request com erro de contrato
(`invalid_request`, `reason: protocol_not_ready`).

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
5. assinar o frame quando a sessao negociada tiver algoritmo de assinatura
compartilhado e `enablePayloadSigning` estiver ativo, ou quando a sessao
negociada exigir assinatura;
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

## Streaming chunked (quando `enableSocketStreamingChunks` ativo; default **off**)

Fluxo atual para resultados grandes:

1. Hub envia `rpc:request` com `sql.execute`.
2. Agente inicia execucao; se resultado exceder limite, retorna resposta inicial
  com `stream_id` e emite `rpc:chunk` para cada lote ordenado.
3. Agente emite `rpc:complete` ao finalizar com `total_rows` e resumo.
  Se o stream for interrompido por backpressure, erro ODBC ou falha de envio apos chunks parciais, o agente emite ainda `rpc:complete` com `terminal_status`: `aborted` (ex.: fila/backpressure) ou `error` (ex.: falha de execucao), para o hub fechar o stream de forma deterministica; o `rpc:response` associado pode ser erro.
4. Se `enableSocketBackpressure`: agente espera `rpc:stream.pull` antes de enviar
  proximos chunks; `window_size` controla quantos chunks enviar por pull.
5. **Overflow de buffer**: se a fila de chunks atingir o limite (`maxBackpressureChunkQueueSize`)
  e o hub nao enviar `rpc:stream.pull` a tempo, o agente **nao descarta** chunks silenciosamente.
   Em vez disso, cancela o stream e retorna erro RPC `resultTooLarge` (`-32105`) com
   `reason: result_too_large` (canonico) e `subreason: backpressure_overflow` (refinamento da causa).
   O hub deve consumir mais rapido ou aumentar `window_size`.

Quando `enableSocketBackpressure` esta ativo, o agente tambem anuncia em
`capabilities.extensions`:

- `recommendedStreamPullWindowSize`: `1` (preserva o modelo atual de credito inicial unitario)
- `maxStreamPullWindowSize`: `maxBackpressureChunkQueueSize` (limite superior recomendado ao hub)

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


| Campo              | Tipo              | Obrigatorio    | Descricao                                                                                                                                                                                                 |
| ------------------ | ----------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `api_version`      | string            | recomendado    | Versao do contrato (ex.: `"2.1"`). O runtime atual aceita requests sem esse campo como compatibilidade com v2.0 implicito e sempre o inclui nas responses quando `enableSocketApiVersionMeta` esta ativo. |
| `meta.trace_id`    | string            | recomendado    | ID de rastreamento distribuido                                                                                                                                                                            |
| `meta.traceparent` | string            | recomendado    | W3C Trace Context principal                                                                                                                                                                               |
| `meta.tracestate`  | string            | opcional       | W3C Trace Context vendor-specific                                                                                                                                                                         |
| `meta.request_id`  | string            | recomendado    | ID unico do request (correlacao)                                                                                                                                                                          |
| `meta.agent_id`    | string            | sim (response) | Identificador do agente                                                                                                                                                                                   |
| `meta.timestamp`   | string (ISO-8601) | sim (response) | Instante UTC do envio. Em requests, e recomendado para rastreabilidade, mas nao exigido pelo runtime atual.                                                                                               |


### Notificacoes (`id` ausente)

- Pedidos **notification** (sem `id` no JSON-RPC) **nao** associam resposta nem correlacao por `id`.

### Nota operacional (largura de banda)

- A compressao outbound continua sendo controlada pela politica local do agente
e pela negociacao de capacidades (`compressions`, `compressionThreshold`,
`maxCompressedPayloadBytes` e afins). Nao existe, no runtime atual, override
por request via `meta`.

### Politica de obrigatoriedade

- Quando `enableSocketApiVersionMeta` esta ativo, `api_version` e `meta`
sao **incluidos automaticamente** pelo agente em toda response.
- Requests do hub **devem** incluir `api_version` e `meta` para rastreabilidade
quando o integrador quiser aderir ao profile v2.1+ completo.
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
- `options.timeout_ms`: teto opcional para a execucao ODBC desta request. O valor
efetivo e o menor entre `timeout_ms` e qualquer budget interno ativo no
runtime (quando `enableSocketTimeoutByStage` estiver ligado).
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
com paginacao nem com `params` nomeados. Com autorizacao por token ativa, cada
statement separado por `;` e avaliado isoladamente (mesmo modelo que
`sql.executeBatch`). O agente detecta multiplos statements com um scanner
leve (strings `'...'`, `"..."`, `[...]`, comentarios `--` e `/* */`), nao com
parser SQL completo: nao cobre backticks estilo MySQL, dollar-quoting
PostgreSQL (`$$`), nem delimitadores tipo `GO` (SQL Server).
- O runtime atual suporta ate **5 parametros nomeados por comando**. Acima disso,
a request e rejeitada com erro de validacao.
- `params.database`: override opcional do banco alvo para a request atual.
Quando `payload.database` estiver presente na politica resolvida do token,
este campo passa a ser obrigatorio e deve coincidir com o valor configurado
apos normalizacao simples (`trim` + case-insensitive).
- `idempotency_key`: deduplicacao **por metodo RPC**. O agente persiste o cache
  como `{method}:{idempotency_key.trim()}` (ex.: `sql.execute:minha-chave`), de
  modo que a mesma string em **outro** `method` nao reutiliza entrada de cache.
  Isso e independente de `request.id` (correlacao JSON-RPC 2.0 no envelope da
  resposta) e de `meta.request_id` (rastreio operacional no `meta` da resposta).
- Reuso no **mesmo** `method` com `params` diferentes: rejeitado com `invalid_params`
  (fingerprint mismatch).
- Com `enableSocketIdempotency` ativo, o cache fica em SQLite local (tabela
  `rpc_idempotency_cache_table`) com TTL por entrada (padrao 300 s; env
  `RPC_IDEMPOTENCY_CACHE_TTL_SECONDS`, limitado entre 60 s e 24 h) e LRU
  (limite tipico 8192 entradas; eviction por `updated_at`); purge best-effort de
  expirados no bootstrap, depois em intervalo fixo durante a execucao do app
  (padrao 15 minutos, `ConnectionConstants.rpcIdempotencyExpiredPurgeInterval`;
  o timer e cancelado em `shutdownApp` antes do fechamento do Drift); linhas
  expiradas tambem sao removidas em leituras.
- Cache de decisoes de autorizacao SQL e cache de politica de token (em memoria)
usam LRU com limite de entradas (padrao 8192 e 2048; configuravel via
`AUTH_DECISION_CACHE_MAX_ENTRIES` e `AUTH_POLICY_CACHE_MAX_ENTRIES` no `.env`)
alem de TTL por entrada. Invalidacao apos alterar token afeta apenas o hash da
credencial afetada quando o segredo e resolvido; caso contrario o agente faz
flush completo desses caches. Contadores de evento no `MetricsCollector`:
`auth_decision_cache_hit`, `auth_decision_cache_miss`, `auth_policy_cache_hit`,
`auth_policy_cache_miss`. Para `sql.execute`, contadores de caminho de resposta:
`rpc_sql_execute_streaming_chunks_response`, `rpc_sql_execute_streaming_from_db_response`,
`rpc_sql_execute_auto_streaming_from_db_response`,
`rpc_sql_execute_prefer_db_streaming_response`,
`rpc_sql_execute_allowlist_db_streaming_response`,
`rpc_sql_execute_materialized_response`, `rpc_stream_terminal_complete_emitted`,
`rpc_stream_terminal_complete_failed`, `rpc_response_ack_retry`,
`rpc_response_ack_fallback_without_ack`.
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
    ]
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
- Quando `item_count` ou `result_set_count` estao presentes, devem coincidir com
o comprimento de `items` e de `result_sets`, respetivamente (validacao
outbound no agente).
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
- `options.timeout_ms`: teto opcional para a execucao ODBC do batch. O valor
efetivo e o menor entre `timeout_ms` e qualquer budget interno ativo no
runtime (quando `enableSocketTimeoutByStage` estiver ligado).
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
- Cada `commands[*].sql` deve conter **exatamente um statement SQL de topo**.
Para scripts com multiplos statements/result sets na mesma execucao, use
`sql.execute` com `options.multi_result: true`.
- O runtime atual suporta ate **5 parametros nomeados por comando**.
- `params.database`: override opcional do banco alvo para o batch atual.
Quando `payload.database` estiver presente na politica resolvida do token,
este campo passa a ser obrigatorio e deve coincidir com o valor configurado
apos normalizacao simples (`trim` + case-insensitive).
- `idempotency_key`: deduplicacao **por metodo RPC**. O agente persiste o cache
  como `{method}:{idempotency_key.trim()}` (ex.: `sql.execute:minha-chave`), de
  modo que a mesma string em **outro** `method` nao reutiliza entrada de cache.
  Isso e independente de `request.id` (correlacao JSON-RPC 2.0 no envelope da
  resposta) e de `meta.request_id` (rastreio operacional no `meta` da resposta).
- Reuso no **mesmo** `method` com `params` diferentes: rejeitado com `invalid_params`
  (fingerprint mismatch).
- Com `enableSocketIdempotency` ativo, o cache fica em SQLite local (tabela
  `rpc_idempotency_cache_table`) com TTL por entrada (padrao 300 s; env
  `RPC_IDEMPOTENCY_CACHE_TTL_SECONDS`, limitado entre 60 s e 24 h) e LRU
  (limite tipico 8192 entradas; eviction por `updated_at`); purge best-effort de
  expirados no bootstrap, depois em intervalo fixo durante a execucao do app
  (padrao 15 minutos, `ConnectionConstants.rpcIdempotencyExpiredPurgeInterval`;
  o timer e cancelado em `shutdownApp` antes do fechamento do Drift); linhas
  expiradas tambem sao removidas em leituras.

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

## Bulk insert nativo (implementado)

### Request (`sql.bulkInsert`)

```json
{
  "jsonrpc": "2.0",
  "method": "sql.bulkInsert",
  "id": "bulk-001",
  "params": {
    "table": "sales.orders",
    "columns": [
      { "name": "id", "type": "i32" },
      { "name": "code", "type": "text", "max_len": 40 },
      { "name": "created_at", "type": "timestamp" }
    ],
    "rows": [
      [1, "A001", "2026-05-14T10:00:00Z"],
      [2, "A002", "2026-05-14T10:00:01Z"]
    ],
    "options": {
      "timeout_ms": 30000
    }
  }
}
```

- Usa o bulk insert nativo do `odbc_fast`, indicado para cargas grandes que
  seriam ineficientes como milhares de comandos em `sql.executeBatch`.
- `table` e `columns[*].name` aceitam caminhos simples de identificador
  (`tabela` ou `schema.tabela`); nomes com quoting especial devem continuar no
  caminho SQL tradicional ate haver contrato explicito para quoting.
- `columns[*].type`: `i32`, `i64`, `text`, `decimal`, `binary`, `timestamp`.
- `rows.length` respeita o limite negociado `max_rows`.
- Autorizacao por `client_token` usa um SQL representativo
  `INSERT INTO <table> (...) VALUES (...)`, preservando a mesma politica por
  tabela do restante do protocolo.

### Response (`sql.bulkInsert`)

```json
{
  "jsonrpc": "2.0",
  "id": "bulk-001",
  "result": {
    "execution_id": "bulk-789",
    "started_at": "2026-05-14T10:00:00Z",
    "finished_at": "2026-05-14T10:00:01Z",
    "table": "sales.orders",
    "row_count": 2,
    "inserted_rows": 2
  }
}
```

- **Ordem do array em batch JSON-RPC:** o agente monta o array de respostas na
ordem crescente do indice do request no batch (mesma ordem de iteracao do
processamento). Notifications nao geram entrada; correlacione cada resposta
pelo `id` JSON-RPC.

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
- `-32015`: Agent actions temporarily unavailable (starting, draining, maintenance, degraded runner)

### Dominio acoes (MVP 3 — codigos compartilhados + `category: action`)

No MVP, falhas de `agent.action.*` **nao** usam faixa numerica propria. O agente reutiliza
codigos de transporte/autorizacao/validacao ja existentes e distingue o dominio por:

- `error.data.category`: `action`
- `error.data.reason`: identificador estavel (`agent_action_permission_denied`,
  `agent_actions_remote_disabled`, `remote_idempotency_required`, codigos de
  `AgentActionFailureCode`, etc.)
- `error.data.failure_code`: codigo tipado do dominio quando a falha veio de use case

Faixa **reservada** para codigos dedicados futuros: `-32299` .. `-32200` (sem uso no MVP;
nao colide com SQL `-321xx`). Quando um codigo dedicado for introduzido, sera documentado
com bump de versao de protocolo.

| Codigo RPC tipico | Cenario agente | `reason` exemplo |
| --- | --- | --- |
| `-32602` | params/schema | `remote_idempotency_required`, `remote_context_not_supported` |
| `-32001` | token ausente/invalido | `missing_client_token` |
| `-32002` | gate remoto ou policy | `agent_actions_remote_disabled`, `agent_action_permission_denied` |
| `-32013` | rate limit remoto | `agent_action_remote_rate_limited` |
| `-32015` | subsistema indisponivel | `agent_actions_draining`, `agent_actions_maintenance_mode` |
| `-32109` | execucao de acao nao encontrada | `execution_not_found` (reuso do codigo SQL) |

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


| Codigo   | Cenario comum                                                                                      | Acao recomendada no cliente                                                                         |
| -------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `-32700` | JSON malformado                                                                                    | corrigir serializacao JSON e reenviar                                                               |
| `-32600` | request invalida                                                                                   | validar contrato antes de enviar                                                                    |
| `-32601` | metodo inexistente                                                                                 | ajustar nome do metodo para um suportado                                                            |
| `-32602` | parametros invalidos                                                                               | corrigir payload antes de reenviar                                                                  |
| `-32603` | erro interno                                                                                       | retry com backoff; se persistir, acionar suporte                                                    |
| `-32001` | falha de autenticacao ou token ausente                                                             | incluir `client_token` em params ou renovar credencial                                              |
| `-32002` | sem permissao (token revogado, nao encontrado, ou negado)                                          | ocultar acao na UI e orientar contato com admin                                                     |
| `-32008` | timeout                                                                                            | retry com backoff e observabilidade                                                                 |
| `-32009` | payload invalido                                                                                   | validar schema e encoding antes do envio                                                            |
| `-32010` | falha de decode                                                                                    | verificar content-type/encoding e compatibilidade                                                   |
| `-32011` | falha de compressao                                                                                | reenviar sem compressao (fallback) e registrar erro                                                 |
| `-32012` | erro de rede                                                                                       | reconectar socket e repetir com controle                                                            |
| `-32013` | cota por janela (`RpcRequestGuard`) **ou** limite de handlers `rpc:request` concorrentes no agente | backoff; reduzir taxa enviada ao agente; ver `technical_message` (distingue janela vs concorrencia) |
| `-32014` | request duplicada (replay)                                                                         | reenviar com novo `id`/correlation                                                                  |


### Formato de erro

O objeto `error.data` segue um formato estruturado para UX e troubleshooting:

- `reason`: identificador estavel do motivo do erro
- `category`: classe do erro para automacao e roteamento
- `retryable`: indica se retry automatico faz sentido
- `user_message`: mensagem amigavel para exibicao
- `technical_message`: detalhe tecnico para logs e suporte
- `correlation_id`: identificador para correlacionar logs
- `timestamp`: instante UTC da falha
- `corrective_action`: token opcional e seguro com orientacao corretiva quando o
  erro vier do subsistema de acoes e ainda nao existir `execution` persistida

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

**Nota**: O cancelamento aplica-se apenas a execucoes em streaming rastreadas pelo
runtime quando `enableSocketCancelMethod` esta ativo. Hoje isso cobre o caminho
de streaming ativo do banco; respostas chunked geradas apos materializacao do
resultado nao sao cancelaveis por este metodo.

## Metodo `agent.getProfile`

- **Onde roda:** tratado no `RpcMethodDispatcher` como metodo de negocio normal.
- **Objetivo:** retornar os dados cadastrais atuais do agente para fluxos de
cadastro/conciliacao no servidor central, sem expor credenciais de auth ou
detalhes de conexao ODBC.
- **Params:** pode ser chamado sem `client_token` pelo hub autenticado na
sessao `/agents`. Chamadores externos podem informar `client_token` (ou aliases
`clientToken` / `auth`) para autorizacao agent-side adicional quando ativa.
`include_diagnostics: true` inclui diagnosticos ODBC; o default e `false` para
manter o sync de perfil barato.
- **Result:** inclui `agent_id`, bloco `profile`, `updated_at` e,
quando conhecido localmente, `profile_version` do catalogo no hub. Quando
`profile_version` existe, `updated_at` usa o timestamp de perfil retornado pelo
hub no ultimo sync, nao o timestamp local de persistencia de configuracao.
O bloco `odbc` so aparece quando `include_diagnostics` e `true`.
- **Erro esperado:** quando nao houver configuracao carregada, o metodo retorna
erro mapeado para o catalogo RPC padrao (via `FailureToRpcErrorMapper`).

## Metodo `agent.getHealth`

- **Onde roda:** tratado no `RpcMethodDispatcher` como metodo de negocio normal.
- **Objetivo:** retornar um snapshot operacional barato do processo do agente,
pool ODBC, fila SQL, metricas de queries e uptime para conciliacao e
observabilidade no hub.
- **Params:** aceita apenas `client_token` (ou aliases `clientToken` / `auth`)
quando a autorizacao por token esta ativa. Com auth ativa, token ausente ou
invalido segue o mesmo mapeamento de erro do fluxo SQL. Params extras sao
rejeitados pelo schema publicado.
- **Result:** objeto alinhado a
`docs/communication/schemas/rpc.result.agent-get-health.schema.json`, com
`status`, `timestamp`, `version`, `pool`, `sql_queue`, `agent_actions`,
`queries`, `batch` e `uptime_seconds`. O bloco `batch` inclui diagnosticos de
paralelismo, caminho transacional e recomendacao de migrar grandes lotes de
`INSERT` para `sql.bulkInsert`. O bloco `agent_actions` e seguro para o Hub e
inclui feature flags efetivas, estado operacional do subsistema e tipos
suportados/indisponiveis.
- **Erros:** os mesmos cenarios de token invalido/ausente/revogado/nao
encontrado que o fluxo de autorizacao SQL, mapeados via
`FailureToRpcErrorMapper`.

## Metodo `agent.action.run`

- **Onde roda:** tratado no `RpcMethodDispatcher` e encaminhado a
`RunAgentActionViaRemoteTrigger`, que resolve um gatilho logico `remote`
habilitado e dispara a mesma fila da UI/scheduler via `DispatchAgentActionTrigger`.
- **Objetivo:** permitir que o Hub solicite a execucao de uma acao local ja
salva e aprovada para remoto **por meio de um gatilho remoto habilitado**. O
metodo nao aceita comando livre nem payload ad-hoc nesta fase e nao aguarda o
processo terminar.
- **Feature flag:** `enableRemoteAgentActions`. Quando desligada, o metodo
responde `-32002` com `reason` `agent_actions_remote_disabled`.
- **Params:** objeto obrigatorio com `action_id` e `idempotency_key`. Opcionalmente
aceita `trigger_id` quando a acao possui mais de um gatilho `remote` habilitado;
caso contrario o agente seleciona automaticamente o unico gatilho `remote`
habilitado. Opcionalmente aceita `trace_id` e `requested_by` para correlacao
(params tem precedencia sobre `meta.trace_id` / `meta.traceparent` e sobre o
requester derivado de meta). Aceita
`client_token` ou aliases `clientToken` / `auth` quando a autorizacao por token
estiver ativa. Contexto inline, `runtimeParameters` e demais chaves extras sao
rejeitados (`reason` `remote_context_not_supported`). Parametros de contexto
inline (`context`, `context_json`, `context_path`, `runtime_parameters`, etc.)
sao rejeitados no schema RPC antes do use case; `extensions.agentActions.supportsContext`
permanece `false` no MVP. Limite documentado para evolucao futura:
`limits.maxContextBytes` (default 256 KiB por acao salva, alinhado a
`ActionContextPolicy.maxContextBytes`). A chave de idempotencia e obrigatoria
para execucao remota e **nao** inclui `trace_id`/`requested_by` na fingerprint
RPC de idempotencia.
- **Rate limit:** opcional por escopo `agent_id` + metodo + `action_id` +
requester (`client_token`, `client_id` ou `hub`). Configuravel por env
`AGENT_ACTION_REMOTE_MAX_PER_MINUTE` (default **0**, sem limite) e
`AGENT_ACTION_REMOTE_MAX_SCOPE_KEYS` (default **8192**). Excesso retorna
`-32013` com `reason` `agent_action_remote_rate_limited`, `action_id`,
`method` e `retry_after_ms`. Retry com a mesma `idempotency_key` e o mesmo
payload permitido retorna a resposta/execucao cacheada antes de consumir nova
cota de rate limit.
- **Idempotencia (duas camadas):** (1) cache RPC SQLite (`{method}:{idempotency_key}`)
  quando `enableSocketIdempotency` esta ativo — TTL por entrada via
  `AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS` (padrao `min(retencao de
  historico de execucoes, 24 h)`; clamp 60 s..3 dias); (2) dedup de negocio em
  `agent_action_execution` por `action_id` + `idempotency_key` enquanto a linha
  existir (retencao `AGENT_ACTION_EXECUTION_RETENTION_DAYS`, padrao 3 dias).
  Fingerprint RPC inclui `runtime_instance_id` / `runtime_session_id` quando
  disponivel (evita replay entre boots).
- **Autorizacao propria:** quando `enableClientTokenAuthorization` estiver
ativa, `client_token` (ou aliases) e obrigatorio; ausencia retorna `-32001` com
`reason` `missing_client_token`. A policy resolvida precisa conter scope de acao `agent_actions.run` em
`payload.agent_actions.scopes`, `payload.agent_action_scopes` ou
`payload.token_scope`. A allowlist opcional de acoes pode ser informada em
`payload.agent_actions.action_ids`; ausente, o scope autoriza qualquer acao que
tambem esteja aprovada localmente. Tokens sem metadados de escopo de acao
(payload legado) continuam autorizados apos o SQL sintetico de autorizacao.
Negacao por escopo/allowlist retorna `-32001` com `reason`
`agent_action_permission_denied` e `data` incluindo `required_scope` e
`action_id` quando aplicavel.
- **Result:** objeto alinhado a
`docs/communication/schemas/rpc.result.agent-action-get-execution.schema.json`,
com snapshot seguro da execucao criada/reutilizada. Para nova execucao remota,
o retorno esperado e o status inicial (`queued` ou estado persistido
idempotente), e o Hub deve consultar `agent.action.getExecution` para acompanhar
`running`/terminal.
- **Erros:** comandos ad-hoc ou parametros extras sao rejeitados pelo schema;
acao sem gatilho `remote` habilitado retorna `invalid_params` com `reason`
`remote_trigger_required`; multiplos gatilhos `remote` sem `trigger_id` retorna
`remote_trigger_ambiguous`; `trigger_id` invalido/desabilitado retorna
`remote_trigger_action_mismatch`, `remote_trigger_type_mismatch` ou
`trigger_disabled`. Acao nao aprovada para remoto, idempotencia ausente, fila
cheia, timeout e falhas de runner retornam erros estruturados via
`FailureToRpcErrorMapper`.
Reuso de `idempotency_key` com payload permitido diferente retorna
`invalid_params` com `reason` `remote_idempotency_fingerprint_mismatch`.
Excesso de chamadas remotas retorna `rate_limited` com `reason`
`agent_action_remote_rate_limited`.
Quando o subsistema de acoes estiver `starting`, `draining`, `maintenance`,
`disabled` ou `degraded` para o tipo solicitado, a chamada deve falhar antes de
enfileirar side effect.
- **Batch:** nao e permitido no MVP. Em JSON-RPC batch, o item retorna
`-32600` com `reason` `method_not_allowed_in_batch` antes de enfileirar.

## Metodo `agent.action.validateRun`

- **Onde roda:** tratado no `RpcMethodDispatcher` e encaminhado ao mesmo use case
local de execucao de acoes (`validateRemoteRun`), **sem** persistir execucao e
**sem** iniciar processo.
- **Objetivo:** permitir que o Hub faca preflight da mesma cadeia de gates de
`agent.action.run` (validacao de request, feature flags, definicao ativa,
aprovacao remota, estado operacional do subsistema, runner registrado,
idempotencia persistida ou em voo, e carga da fila) e receba um resumo seguro
antes de chamar `agent.action.run`.
- **Feature flag:** `enableRemoteAgentActions`. Quando desligada, o metodo
responde `-32002` com `reason` `agent_actions_remote_disabled`.
- **Params:** objeto obrigatorio com `action_id` e `idempotency_key` (mesma
semantica que `run`, incluindo `trace_id`/`requested_by` opcionais). Aceita
`client_token` ou aliases `clientToken` / `auth` quando a autorizacao por token
estiver ativa. Parametros extras sao rejeitados pelo schema publicado.
- **Rate limit:** opcional por escopo `agent_id` + metodo + `action_id` +
requester (`client_token`, `client_id` ou `hub`), com o mesmo mecanismo de
`agent.action.run` (inclui `metodo` = `agent.action.validateRun` na chave).
Configuravel por env `AGENT_ACTION_REMOTE_MAX_PER_MINUTE` (default **0**, sem
limite) e `AGENT_ACTION_REMOTE_MAX_SCOPE_KEYS` (default **8192**). Excesso
retorna `-32013` com `reason` `agent_action_remote_rate_limited`.
- **Autorizacao propria:** quando `enableClientTokenAuthorization` estiver
ativa, `client_token` (ou aliases) e obrigatorio; ausencia retorna `-32001` com
`reason` `missing_client_token`. A policy precisa do scope
`agent_actions.validate_run` (alem de `agent_actions.run` quando for executar de
fato). Allowlist opcional por `action_id` segue a mesma regra de `run`.
- **Result:** objeto alinhado a
`docs/communication/schemas/rpc.result.agent-action-validate-run.schema.json`
(`valid`, `action_id`, `action_type`, `definition_snapshot_hash` opcional,
`would_replay_existing_execution`, `existing_execution_id` opcional).
- **Erros:** mesmos cenarios de negacao de `run` ate a admissao na fila (acao
inativa, remoto nao aprovado, idempotencia ausente para Hub, subsistema em
`starting`/`draining`/etc., fila cheia ou politica de concorrencia que rejeitaria
enqueue), mapeados via `FailureToRpcErrorMapper`. Nao ha cache de idempotencia
RPC separado para este metodo.
- **Batch:** permitido em JSON-RPC batch (sem efeito colateral), como
`agent.action.getExecution`. Itens `run`/`cancel` em batch continuam
rejeitados com `method_not_allowed_in_batch`.

## Metodo `agent.action.getExecution`

- **Onde roda:** tratado no `RpcMethodDispatcher` como metodo de negocio normal.
- **Objetivo:** retornar ao Hub um snapshot redigido de uma execucao de acao do
agente, sem expor comando bruto, argumentos sensiveis, stack trace ou valores
de segredo.
- **Feature flag:** `enableRemoteAgentActions`. Quando desligada, o metodo
responde `-32002` com `reason` `agent_actions_remote_disabled`.
- **Params:** objeto obrigatorio com `execution_id`. Opcionalmente aceita
`stdout_offset`, `stderr_offset` (offsets UTF-8 em bytes sobre stdout/stderr
redigidos ja persistidos) e `max_output_bytes` (tamanho maximo da janela por
stream; default `65536`, teto `524288`). Aceita `client_token` ou aliases
`clientToken` / `auth` quando a autorizacao por token estiver ativa. Quando
`enableClientTokenAuthorization` estiver ativa, ausencia de token retorna `-32001`
com `reason` `missing_client_token`. Com token, exige scope proprio
`agent_actions.read_execution`.
- **Batch:** permitido em JSON-RPC batch (read-only). Respeita o mesmo limite
de itens por batch e a validacao estrita de batch quando habilitados. Diferente
de `agent.action.run` e `agent.action.cancel`, que retornam `-32600` com
`reason` `method_not_allowed_in_batch` antes de executar efeito colateral.
`agent.action.validateRun` tambem e permitido em batch (preflight sem side
effect). O numero de itens read-only (`getExecution` + `validateRun`) no batch
nao pode exceder `extensions.agentActions.limits.maxReadMethodsPerBatch`
(default `32`, env `AGENT_ACTION_MAX_READ_RPC_PER_BATCH`); acima disso o batch
inteiro e rejeitado com `-32600` e `reason` `agent_action_batch_read_limit_exceeded`
(um unico erro de batch, sem dispatch parcial).
- **Result:** objeto alinhado a
`docs/communication/schemas/rpc.result.agent-action-get-execution.schema.json`,
com identificadores, status, timestamps, origem, processo, saida capturada ja
redigida (`output.stdout` / `output.stderr` com `text`, `utf8_total_bytes`,
`offset`, `next_offset`, `response_truncated` e `truncated` de armazenamento),
flags e failure segura (`code`, `phase`, `corrective_action`, `message`) quando
houver falha registrada. O Hub deve paginar com `next_offset` ate
`response_truncated` ser `false` em cada stream.
- **Erros:** `execution_not_found` quando a execucao nao existir; erros de
token e rate limit usam o catalogo RPC padrao. A resposta nunca retorna o
comando bruto salvo na acao.

## Metadados de policy para `agent.action.*` (client token)

Quando `enableClientTokenAuthorization` estiver ativa, o Hub deve emitir tokens cuja
policy resolvida (`client_token.getPolicy` / payload persistido) declare escopos de
acao sem reutilizar `global_permissions` SQL (select/insert/...). Formas suportadas:

| Campinho | Formato | Efeito |
|--------|---------|--------|
| `payload.token_scope` | string ou lista | Escopos OAuth-style (`agent_actions.run`, `agent_actions.*`, etc.) |
| `payload.agent_action_scopes` | lista de strings | Mesma semantica de escopos |
| `payload.agent_actions.scopes` | lista de strings | Escopos no bloco de acoes |
| `payload.agent_actions.action_ids` | lista de strings | Allowlist opcional de `action_id`; quando presente, restringe run/validate/cancel/getExecution ao conjunto |

Escopos canonicos publicados em `extensions.agentActions.authorizationScopes` no
`agent:capabilities`. O agente ainda executa um SQL sintetico por metodo
(`AgentActionRpcConstants.clientTokenAuthorizationSql*`) para validar o token via
pipeline SQL existente; a checagem de escopo/allowlist ocorre **antes** desse SQL.

## Auditoria remota append-only (`agent.action.*`)

Quando `enableAgentActionRemoteAudit` estiver ativa, o agente grava linhas locais
em Drift (sem segredos) para diagnostico do Hub:

- **Por RPC:** `received` na entrada do handler e desfecho final `success`,
  `rpc_error`, `authorization_denied`, `notification_rejected` ou `rate_limited`
  (com `client_id`/`token_jti` quando a policy de client token foi resolvida).
  Negacoes de credencial ou gate remoto (`missing_client_token`,
  `agent_action_permission_denied`, `agent_actions_remote_disabled`,
  `agent_actions_feature_disabled`) usam `authorization_denied`; demais erros RPC
  usam `rpc_error`.
- **Por execucao remota:** `lifecycle_enqueued`, `lifecycle_started`,
  `lifecycle_cancel_requested` (cancel) e `lifecycle_finished` (status terminal
  em `reason_code`), somente para execucoes com origem `remoteHub`.

`trace_id`, `requested_by` e `idempotency_key` (quando presente em `run`/`validateRun`)
propagam para execucao e auditoria via params (opcional) ou `meta` do envelope RPC
(`trace_id`/`requested_by` apenas em `meta`; idempotencia de negocio vem de params).

## Metodo `agent.action.cancel`

- **Onde roda:** tratado no `RpcMethodDispatcher` e encaminhado ao use case
local `CancelAgentActionExecution`.
- **Objetivo:** cancelar uma execucao de acao `queued` ou `running` ja
registrada no Plug Agente. Para processos, o cancelamento mira somente o
processo principal registrado pelo agente.
- **Feature flag:** `enableRemoteAgentActions`. Quando desligada, o metodo
responde `-32002` com `reason` `agent_actions_remote_disabled`.
- **Params:** objeto obrigatorio com `execution_id`. Aceita `client_token` ou
aliases `clientToken` / `auth` quando a autorizacao por token estiver ativa.
- **Autorizacao propria:** quando `enableClientTokenAuthorization` estiver
ativa, `client_token` (ou aliases) e obrigatorio; ausencia retorna `-32001` com
`reason` `missing_client_token`. Com token, exige scope `agent_actions.cancel` e
aplica allowlist opcional por actionId quando disponivel no payload de policy.
- **Result:** objeto alinhado a
`docs/communication/schemas/rpc.result.agent-action-cancel.schema.json`, com
`cancelled`, `execution_id`, `status`, `reason` e snapshot redigido da execucao.
- **Erros:** diferencia `execution_not_found`, `already_finished`,
`agent_action_permission_denied` e `kill_failed`; falhas adicionais de fila ou
runner e rate limit usam o catalogo RPC seguro.
- **Batch:** nao e permitido no MVP. Em JSON-RPC batch, o item retorna
`-32600` com `reason` `method_not_allowed_in_batch` antes de cancelar.

## Metodo `client_token.getPolicy`

- **Onde roda:** tratado no `RpcMethodDispatcher` como metodo de negocio normal.
- **Objetivo:** retornar a **politica de autorizacao** ja resolvida para o token
apresentado (mesmo pipeline que valida `sql.execute`: store local por hash,
cache, JWT/JWKS quando aplicavel, revogacao em sessao). Serve para introspecao
no hub (permissao por recurso, flags `all_tables` / `all_views`,
`global_permissions`, `all_permissions` legado derivado, regras `allow`/`deny`,
`payload` livre), sem executar SQL.
- **Params:** aceita apenas `client_token` (ou aliases `clientToken` / `auth`),
com as mesmas regras de schema que `agent.getProfile`. Quando
`enableClientTokenAuthorization` esta **desligado**, o metodo responde com erro
de parametros (`-32602`) com `reason` `client_token_authorization_disabled`.
Quando `enableClientTokenPolicyIntrospection` esta **desligado** (default
**true**), responde `-32602` com `reason` `client_token_introspection_disabled`.
- **Rate limit:** por escopo `agent_id` + hash do credential (mesmo minuto UTC);
limite configuravel por env `CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE` (default
**120**; **0** = sem limite). Para limitar crescimento do mapa interno com
muitos tokens distintos no mesmo minuto, use `CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS`
(default **8192**; **0** = sem teto por quantidade de escopos). Excesso de
chamadas retorna `-32013` com `reason` `client_token_get_policy_rate_limited`
e, em `error.data`, `retry_after_ms` (milissegundos ate o proximo minuto UTC)
e `reset_at` (ISO 8601 do fim da janela).
- **Result:** objeto alinhado a `ClientTokenPolicy` (`client_id`, `agent_id`
opcional, `payload` com chaves sensiveis redigidas como `[REDACTED]`,
`all_tables`, `all_views`, `global_permissions`, `all_permissions`,
`is_revoked`, `rules` com `resource_type`, `resource`, `effect`, `read`,
`update`, `delete`, `ddl`). Campos opcionais quando disponiveis: `token_id`
(id do registro local ou `jti` do JWT), `issued_at`, `updated_at` (ISO 8601).
`payload.database`, quando presente, oficializa uma restricao extra para
`sql.execute` e `sql.executeBatch`: a request deve informar o mesmo `database`.
**Nao** inclui o segredo do token nem `token_value`.
- **Diferenca vs `agent.getProfile`:** este metodo descreve **permissao do
token**; `agent.getProfile` descreve **cadastro do agente** em configuracao
local.
- **Diferenca vs `sql.execute`:** nao executa consulta no banco; apenas resolve e
devolve politica.
- **Erros:** os mesmos cenarios de token invalido/ausente/revogado/nao encontrado
que o fluxo de autorizacao SQL, mapeados via `FailureToRpcErrorMapper`
(por exemplo `-32001` autenticacao, `-32002` autorizacao com `reason` em
`error.data`).
- **Transporte:** com auth e introspecao ativos, o cliente de transporte aplica a mesma
heuristica de log/refresh de token que para `sql.`* (ex.: `token_revoked` ou
falha de autenticacao pode solicitar refresh da credencial).
- **Observabilidade:** contadores `rpc_client_token_get_policy_`* no
`MetricsCollector` (sucesso, falha de resolucao agregada, falhas por tipo de
`Failure`, rate limit).

## Metodo `rpc.discover`

- **Onde roda:** tratado no transporte (`SocketIOTransportClientV2`) **antes** do
`RpcMethodDispatcher`; nao passa por `sql.execute` nem exige `client_token`.
- **Resultado:** corpo do documento OpenRPC publicado (`docs/communication/openrpc.json`),
carregado de asset em runtime com fallback para disco e documento minimo embutido.
- **Batch:** cada item de batch com `method: "rpc.discover"` e processado da mesma
forma no loop do transporte.
- **Notifications e contrato estrito:** com `enableSocketNotificationsContract`
ativo, um pedido **sem** `id` (notification JSON-RPC) **nao** recebe
`rpc:response` — regra geral de notifications. Para obter o OpenRPC, o hub deve
enviar `rpc.discover` com `id` definido.

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


| Codigo   | `reason` recomendado                                                                                                           |
| -------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `-32700` | `json_parse_error`                                                                                                             |
| `-32600` | `invalid_request` ou `protocol_not_ready`                                                                                      |
| `-32601` | `method_not_found`                                                                                                             |
| `-32602` | `invalid_params`                                                                                                               |
| `-32603` | `internal_error`                                                                                                               |
| `-32001` | `authentication_failed`, `missing_client_token` ou `invalid_signature` (falha de HMAC no `PayloadFrame` ou no envelope logico) |
| `-32002` | `unauthorized` (ex.: `token_revoked`, `token_not_found`)                                                                       |
| `-32008` | `timeout`                                                                                                                      |
| `-32009` | `invalid_payload`                                                                                                              |
| `-32010` | `decoding_failed`                                                                                                              |
| `-32011` | `compression_failed`                                                                                                           |
| `-32012` | `network_error`                                                                                                                |
| `-32013` | `rate_limited`                                                                                                                 |
| `-32014` | `replay_detected`                                                                                                              |
| `-32101` | `sql_validation_failed`                                                                                                        |
| `-32102` | `sql_execution_failed`                                                                                                         |
| `-32103` | `transaction_failed`                                                                                                           |
| `-32104` | `connection_pool_exhausted`                                                                                                    |
| `-32105` | `result_too_large`                                                                                                             |
| `-32106` | `database_connection_failed`                                                                                                   |
| `-32107` | `query_timeout`                                                                                                                |
| `-32108` | `invalid_database_config`                                                                                                      |


Regras:

- `reason` deve ser estavel e orientado a automacao.
- `message` pode variar menos, mas `reason` e o identificador principal.
- `user_message` pode ser localizado; `reason` nao.
- O campo opcional `odbc_reason` em `error.data` guarda um sub-motivo de dominio quando ele difere do `reason` canônico do código RPC (ex.: motivos ODBC como `connection_timeout`, `server_unreachable`, ou motivos de autorização como `missing_permission`, `token_revoked`). O identificador principal para automação continua sendo `reason`.
- Para falhas ODBC de conexao ou pool (`-32104`, `-32106`), o agente define `reason` no valor canônico da tabela acima (`connection_pool_exhausted`, `database_connection_failed`).
- Se a sessao cair durante a execucao SQL (ex.: SQLSTATE classe `08` / link de comunicacao), o erro pode ser classificado como `database_connection_failed` (`-32106`) com sub-motivo `connection_lost_during_query` em `odbc_reason` quando aplicavel.

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

- **Reconexao curta** (`ConnectionProvider` + `computeReconnectDelay`): apos
desconexao, o agente agenda atrasos com backoff exponencial a partir de
**5 s** por tentativa (`AppConstants.reconnectIntervalSeconds`), multiplicador
**2^(tentativa-1)** (ex.: ~5 s, ~10 s, ~20 s antes das tentativas 1..3), com
**teto de 60 s** por intervalo (`maxReconnectDelay`) e **jitter** de ±15%.
- **Max tentativas**: 3 tentativas por ciclo de recovery
(`AppConstants.maxReconnectAttempts` / `ConnectionConstants.defaultMaxReconnectAttempts`).
- **Token expirado**: ao detectar `token_revoked` ou `authentication_failed`, o
agente tenta refresh via AuthProvider e reconecta com token renovado.
- **Heartbeat**: `agent:heartbeat` a cada 20s; ausencia de `hub:heartbeat_ack`
em 2 janelas consecutivas aciona reconexao.

### Rate limiting e cota de concorrencia (agent-side)


| Parametro                  | Valor padrao              | Descricao                                                              |
| -------------------------- | ------------------------- | ---------------------------------------------------------------------- |
| `rateLimitWindow`          | 1 minuto                  | Janela deslizante para contagem de eventos recebidos                   |
| `maxRequestsPerWindow`     | 120                       | Maximo de eventos contados na janela antes do guard de taxa            |
| `maxConcurrentRpcHandlers` | 32                        | Maximo de `rpc:request` **em processamento assincrono** ao mesmo tempo |
| Codigo de erro (ambos)     | `-32013` (`rate_limited`) | HTTP 429; `error.data.reason` permanece `rate_limited`                 |


O codigo `-32013` e reutilizado para duas politicas independentes: (1) excesso de
volume na janela deslizante (`RpcRequestGuard`) e (2) saturacao do pool de
handlers concorrentes no transporte. O hub/cliente deve usar
`error.data.technical_message` para distinguir (ex.: mensagem contem
`Concurrent RPC handler limit exceeded`).

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

Exemplo de capacidades anunciadas (alinhado a
`ProtocolCapabilities.defaultCapabilities` quando `binaryPayload` esta ativo):

```json
{
  "protocols": ["jsonrpc-v2"],
  "encodings": ["json"],
  "compressions": ["gzip", "none"],
  "extensions": {
    "batchSupport": true,
    "binaryPayload": true,
    "transportFrame": "payload-frame/1.0",
    "compressionThreshold": 4096,
    "protocolReadyAck": true,
    "maxInflationRatio": 10,
    "signatureRequired": false,
    "signatureScope": "transport-frame",
    "signatureAlgorithms": ["hmac-sha256"],
    "streamingResults": true,
    "agentActions": {
      "enabled": true,
      "version": 1,
      "methods": [
        "agent.action.run",
        "agent.action.validateRun",
        "agent.action.cancel",
        "agent.action.getExecution"
      ],
      "supportedMethods": [
        "agent.action.run",
        "agent.action.validateRun",
        "agent.action.cancel",
        "agent.action.getExecution"
      ],
      "supportedTypes": ["commandLine"],
      "supportsRun": true,
      "supportsValidateRun": true,
      "supportsDryRun": true,
      "supportsCancel": true,
      "supportsGetExecution": true,
      "supportsOutputPaging": true,
      "supportsContext": false,
      "requiresIdempotencyKey": true,
      "authorizationScopes": [
        "agent_actions.run",
        "agent_actions.validate_run",
        "agent_actions.cancel",
        "agent_actions.read_execution"
      ],
      "remoteAdHoc": false,
      "elevatedAllowed": false,
      "supportsElevated": false,
      "status": "ready",
      "maintenanceMode": false,
      "unavailableTypes": [],
      "defaultQueueLimits": {
        "maxConcurrent": 1,
        "maxQueued": 100,
        "queueTimeoutMs": 300000
      },
      "limits": {
        "maxConcurrentActions": 1,
        "maxQueuedActions": 100,
        "maxContextBytes": 262144,
        "defaultMaxOutputBytesPerStream": 65536,
        "maxMaxOutputBytesPerStream": 524288,
        "supportsOutputPaging": true,
        "maxReadMethodsPerBatch": 32
      },
      "batchPolicy": {
        "run": false,
        "cancel": false,
        "validateRun": true,
        "getExecution": true
      },
      "profile": "prod",
      "agentEnvironment": "prod"
    },
    "plugProfile": "plug-jsonrpc-profile/2.11.2",
    "orderedBatchResponses": true,
    "notificationNullIdCompatibility": true,
    "paginationModes": ["page-offset", "cursor-keyset", "cursor-offset"],
    "traceContext": ["w3c-trace-context", "legacy-trace-id"],
    "errorFormat": "structured-error-data"
  }
}
```

Quando o backpressure esta ativo, o mesmo bloco `extensions` tambem pode incluir
`recommendedStreamPullWindowSize` e `maxStreamPullWindowSize`.

O mapa `limits` negociado segue a secao "Limites negociados por transporte"; nao
e repetido neste exemplo.

O array `compressions` no handshake reflete o que o agente **anuncia** para o
hub (`gzip` + `none` quando compressao outbound nao esta desligada, ou apenas
`none` quando o modo outbound e `none`). O modo **automatico** de compressao
(`OutboundCompressionMode.auto`) nao adiciona um terceiro valor no fio: o frame
continua com `cmp: gzip` ou `cmp: none`. Quem recebe usa apenas esses campos
por mensagem; **nao** infere o modo local do emissor (Automatico vs Sempre GZIP).

## Compatibilidade e Fallback

- O agente transmite eventos de aplicacao em `PayloadFrame` binario.
- O runtime atual **nao** aceita payload logico JSON cru em eventos de
aplicacao; clientes devem sempre enviar `PayloadFrame`.
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
3. Lookup local: hash SHA-256 do token -> SQLite -> politica (regras, all_tables, all_views, global_permissions e `all_permissions` legado derivado).
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

### Resposta em caso de negacao de autorizacao

- Em `error.data` (codigo `-32002` / `unauthorized`), alem de `resource` (primeiro recurso negado, compatibilidade), o agente envia `denied_resources`: lista ordenada de nomes normalizados de tabelas/views sem permissao para a operacao naquela instrucao SQL. O campo `user_message` descreve a operacao e cita os recursos para facilitar pedidos de liberacao.

## Observabilidade de autorizacao (implementado)

- Coleta de metricas de autorizacao em memoria (allow/deny, por operacao, recurso e motivo).
- Logs estruturados no transporte para decisoes de autorizacao no fluxo RPC (`authorization.allowed` e `authorization.denied`).
- Exibicao de resumo de autorizacao no dashboard via `WebSocketLogViewer`.
- Quando o RPC retorna `authentication_failed` ou `token_revoked`, o transporte
dispara callback de refresh de token/reconexao.
- Contadores operacionais em memoria para observabilidade de resiliencia:
`timeout_cancel_success`, `timeout_cancel_failure`,
`transaction_rollback_failure` e `idempotency_fingerprint_mismatch`.
- Decodificacao inbound do `PayloadFrame` (apos validacao do frame):
`transport_inbound_decode_sync` e `transport_inbound_decode_async`
(`MetricsCollector`), para distinguir caminho sincrono vs isolate em cargas
grandes ou gzip pesado.

## Politica de versao e deprecacao

### Versionamento


| Versao | Descricao                                                                                                             | Status |
| ------ | --------------------------------------------------------------------------------------------------------------------- | ------ |
| `2.0`  | JSON-RPC 2.0 base (sql.execute, sql.executeBatch, erros)                                                              | stable |
| `2.1`  | Extensoes: api_version, meta, client_token auth, notifications                                                        | stable |
| `2.2`  | Hardening de limites negociados e assinatura de payload                                                               | stable |
| `2.3`  | Profile formal, OpenRPC, observabilidade e cursor opaco                                                               | stable |
| `2.4`  | Cursor keyset, output validation e `rpc.discover`                                                                     | stable |
| `2.5`  | execution_mode preserve, alias legado e metadata de handling                                                          | stable |
| `2.6`  | Cadastro do agente no handshake e metodo `agent.getProfile`                                                           | stable |
| `2.7`  | Metodo `client_token.getPolicy` para introspecao de politica do token                                                 | stable |
| `2.8`  | `getPolicy`: metadata opcional, redacao de payload, rate limit, flag `enableClientTokenPolicyIntrospection`, metricas | stable |
| `2.9`  | Metodo `agent.getHealth` para saude do processo, pool ODBC, fila SQL e metricas de queries                           | stable |
| `2.10` | Metodo `sql.bulkInsert` para cargas grandes via bulk insert nativo ODBC                                              | stable |
| `2.11` | Metodos `agent.action.run`, `agent.action.cancel` e `agent.action.getExecution` para execucao remota conservadora   | experimental |
| `2.11.1` | Metodo `agent.action.validateRun` (preflight remoto sem side effect) e escopo `agent_actions.validate_run` | experimental |
| `2.11.2` | Status/flags explicitos de `skipped` em `agent.action.getExecution` e counters de health para terminais `skipped` | experimental |


### Regras de versionamento

- **Semver no contrato**: versoes `major.minor`. Major = breaking change; minor = extensao compativel.
- `**api_version`** no payload indica a versao do contrato que o emissor espera.
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

- **Opcional antes da negociacao obrigatoria**: o emissor pode omitir
`signature`; o receptor aceita sem verificar enquanto a sessao nao exigir
assinatura.
- **Verificacao**: quando presente, o receptor **deve** verificar. Se invalida,
retorna `-32001` (`Authentication failed`) com `error.data.reason`:
`invalid_signature` (frame de transporte ou assinatura legada no JSON logico).
Se o frame vier assinado e o receptor nao tiver chave para verificar, o frame
tambem e rejeitado como assinatura invalida.
- **Politica negociada**: depois de `agent:capabilities`, o valor negociado
`signatureRequired` e autoritativo. Se o hub exigir assinatura e o agente nao
tiver signer configurado ou algoritmo comum, a negociacao falha explicitamente.
- **Escopo principal**: a assinatura cobre `schemaVersion`, `enc`, `cmp`,
`contentType`, tamanhos, `traceId`, `requestId` e os bytes do `payload`.
- **Canonicalizacao**: o HMAC usa JSON canonico UTF-8 sem espacos, com chaves de
objetos ordenadas lexicograficamente em todos os niveis. No `PayloadFrame`, o
campo `payload` entra na entrada canonica como base64 dos bytes transmitidos e
o campo `signature` nunca participa da assinatura.
- **Compatibilidade**: quando o modo binario estiver desativado por feature
flag, a assinatura legada sobre o payload logico JSON continua sendo aceita.
- **Algoritmos suportados**: `hmac-sha256` (inicial). Extensivel para `ed25519` no futuro.
- **Key management**: chaves compartilhadas ficam no secure storage local. As
variaveis `PAYLOAD_SIGNING_KEY`/`PAYLOAD_SIGNING_KEY_ID` continuam aceitas para
bootstrap legado e sao migradas para storage seguro quando possivel.
`PAYLOAD_SIGNING_KEYS_JSON` ou `PAYLOAD_SIGNING_KEYS` permitem multiplas chaves;
`PAYLOAD_SIGNING_ACTIVE_KEY_ID` define a chave ativa de assinatura. O agente
assina com a chave ativa e verifica com qualquer `key_id` configurado.

### Feature flag

- `enablePayloadSigning`: quando ativo, o agente assina frames de saida apenas
se houver signer configurado e algoritmo compartilhado negociado. Antes de
`agent:capabilities`, assinatura outbound opcional fica desativada para evitar
quebrar hubs sem chave; o agente so assina antes da negociacao quando a
configuracao local exige assinaturas inbound.
- `requireIncomingPayloadSignatures`: quando ativo, o agente exige assinatura em
frames de entrada antes da negociacao. Apos `agent:capabilities`, prevalece
`signatureRequired` negociado.

### Implementacao

- Classe `PayloadSigner` em `infrastructure/security/payload_signer.dart`.
- Canonicalizacao em `infrastructure/security/payload_signing_canonicalizer.dart`.
- Chaves resolvidas por `PayloadSigningKeyResolver`: secure storage local,
bootstrap por env legado e suporte a multiplas chaves para rotacao.
- Rotacao controlada: `PayloadSigningConfig` oferece operacoes atomicas locais
para adicionar chave, ativar `key_id` existente e remover chave antiga
(`upsertKey`, `activateKey`, `removeKey`). Persistir o resultado via
`PayloadSigningKeyStore.save()` antes de exigir a chave nova no hub.
- Integrado ao `SocketIOTransportClientV2`: assina frames enviados e verifica
frames recebidos.
- Diagnostico visivel no tracer WebSocket: evento
`payload_signing:diagnostic` com estado de signer, fonte da chave, `key_id`
ativo, quantidade de chaves e politica negociada, sem expor segredos.
- O diagnostico tambem inclui um bloco `health` derivado de
`PayloadSigningDiagnostics`, com status (`ok`, `warning`, `error`), issues
acionaveis, estado de rotacao (`rotation_ready`) e disponibilidade de secure
storage. A UI de configuracao exibe esses alertas antes de conectar.
- Vetores de contrato HMAC em `test/fixtures/payload_signing_test_vectors.json`
para alinhamento com o hub.
- Comparacao constant-time para prevenir timing attacks.
- Feature flag `enablePayloadSigning` (default `false`).

## Limites operacionais atuais

- `options.timeout_ms` suportado em `sql.execute` e `sql.executeBatch`.
Quando timeouts por estagio do socket estao ativos, o timeout ODBC efetivo do
batch e o **minimo** entre o orcamento do estagio SQL e `options.timeout_ms`
(este ultimo age como teto por pedido). Em `sql.executeBatch` com
`transaction: false`, o agente aplica o **tempo restante** do orcamento a cada
comando em sequencia; se o orcamento esgotar antes de um comando, o batch
falha com contexto de timeout/budget (sem executar esse comando).
- `options.max_rows` suportado em `sql.execute` e `sql.executeBatch`.
- `options.max_parallel_read_only_batch_items` suportado em `sql.executeBatch`
  para lotes nao transacionais compostos apenas por `SELECT`; e opt-in e o
  agente aplica cap interno de seguranca baseado no pool ODBC. Esse cap e
  global por gateway, portanto batches simultaneos competem pelos mesmos tokens
  e nao multiplicam o consumo de conexoes do pool. O health expoe
  `batch.parallel_global_wait_avg_ms`, `parallel_global_wait_p95_ms`,
  `parallel_global_wait_p99_ms` e `parallel_global_wait_sample_count`.
- Grandes lotes homogeneos de `INSERT` em `sql.executeBatch` continuam
  suportados, mas o agente incrementa `batch.bulk_insert_recommended_total`
  para orientar migracao para `sql.bulkInsert`, que usa o bulk insert nativo
  ODBC.
- `ODBC_DIRECT_CONNECTION_MAX_CONCURRENT` pode sobrescrever o limite de
  conexoes ODBC diretas usadas por streaming/fallback. Sem override, o agente
  reserva metade do tamanho do pool para esses caminhos. Overrides maiores que
  o pool ODBC sao capados no tamanho do pool e aparecem no health como
  `direct_connections.override_exceeds_pool=true`. O health tambem expoe
  `direct_connections.wait_avg_ms`, `wait_p95_ms`, `wait_p99_ms` e
  `wait_sample_count` para diagnosticar saturacao desse limiter.
- `ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST` permite habilitar o caminho
  native-compatible experimental para SQLs simples e conhecidas, separadas por
  `|`, por exemplo `select id from users|select name from departments`. O match
  e exato apos normalizacao simples de whitespace/case; consultas com
  `SELECT *` continuam fora desse caminho. A allowlist e cacheada por curto TTL
  e reprocessada quando o valor de ambiente muda.
- `options.page` e `options.page_size` suportados em `sql.execute`.
- `options.cursor` suportado em `sql.execute`.
- `options.execution_mode` suportado em `sql.execute`.
- `options.preserve_sql` suportado em `sql.execute` como alias legado.
- `options.prefer_db_streaming` suportado em `sql.execute` para preferir
  streaming direto do banco em `SELECT` sem paginacao quando o recurso esta
  habilitado e negociado.
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
- O payload logico dentro do frame continua sendo **JSON UTF-8**; o frame
binario reduz overhead de transporte e suporta bytes/signature, mas **nao**
significa que o runtime atual use MessagePack, Protobuf ou outro codec
binario real.
- O runtime atual nao oferece fallback para payload logico JSON cru em eventos
de aplicacao.
- A compressao de **envio** (agente -> hub) segue o limiar negociado
`compressionThreshold`. No modo **automatico** (`OutboundCompressionMode.auto`
nas configuracoes do agente), o GZIP e aplicado apenas quando o bloco
comprimido e **menor** que o JSON UTF-8 bruto; caso contrario o frame usa
`cmp: none` (mesmo acima do limiar). No modo **sempre GZIP**, o emissor prefere
gzip quando o tamanho atinge o limiar, mas ainda cai para `cmp: none` quando o
frame comprimido violaria `maxInflationRatio`. Clientes devem aceitar
`cmp: gzip` e `cmp: none` em qualquer frame recebido.
- O runtime atual **nao** suporta sobrescrever essa politica por request via
`meta`; a negociacao `compressions: none` na sessao continua a impedir GZIP
outbound.
- Nao existe metodo RPC generico de transferencia de arquivo no contrato atual;
qualquer conteudo de arquivo precisa ser modelado no payload logico do metodo
e, depois, transportado dentro do `PayloadFrame`.
- Metodo `sql.cancel` disponivel via feature flag `enableSocketCancelMethod`
(cancela execucao em streaming ativa; execucoes nao-streaming nao sao
cancelaveis).
- Streaming chunked: opt-in via `enableSocketStreamingChunks` (default **off**);
resultados acima de `streaming_row_threshold` negociado sao enviados em chunks
(`rpc:chunk`, `rpc:complete`) quando a flag esta ligada.
- `capabilities.extensions.streamingResults` e negociado entre agente e hub.
  Quando `enableSocketStreamingFromDb` esta ativo, o agente pode criar emissor
  de stream para consultas `SELECT` elegiveis mesmo que o chunking materializado
  geral esteja desligado. O roteamento automatico considera SQLs grandes,
  sinais textuais de consulta pesada, `options.prefer_db_streaming` e allowlist
  operacional `DB_STREAMING_AUTO_TABLE_ALLOWLIST`. A allowlist aceita `*`,
  nomes simples (`users`) e nomes qualificados (`public.users`), separados por
  virgula. CTEs, joins e subqueries exigem `options.prefer_db_streaming=true`
  para evitar roteamento automatico por heuristica parcial.
- Backpressure: opt-in via `enableSocketBackpressure` (default **off**); o hub
envia `rpc:stream.pull` com `window_size` para controlar quantos chunks o
agente envia por vez; credito inicial de 1 chunk.
- `api_version`/`meta` disponiveis via feature flag `enableSocketApiVersionMeta`;
contrato formal na secao "api_version e meta".
- `agent:ready` e enviado apos `agent:capabilities` como ack explicito de
prontidao; hubs antigos podem ignorar o evento sem impacto funcional.
- Notification JSON-RPC (sem `id`) formalizada na secao "Notification JSON-RPC";
enforcement via `enableSocketNotificationsContract`.
- Regras estritas de batch formalizadas na secao "Regras formais de batch";
enforcement via `enableSocketBatchStrictValidation`.
- Timeout por etapa (SQL, transporte, ack) disponivel via
`enableSocketTimeoutByStage`; erros incluem `reason` especifico
(`query_timeout`, `transport_timeout`, `ack_timeout`).
- Em timeout de SQL, o agente aplica cancelamento best-effort da execucao no
banco (desconexao/recuperacao de conexao) para evitar trabalho zumbi.
- Garantia de entrega por tipo de evento: opt-in via
`enableSocketDeliveryGuarantees` (default **off**); ver tabela abaixo quando
ativo.
- Connection state recovery com retry/backoff esta ativo agent-side.
- Politica de refresh/auth no reconnect esta ativa agent-side.
- Rate limits/quotas por evento estao ativos agent-side.
- Schemas JSON publicados em `docs/communication/schemas/`. Validacao automatica
na entrada disponivel via `enableSocketSchemaValidation`.
- Validacao de contrato na **saida** (`rpc:response`, respostas batch e eventos
de streaming) via `enableSocketOutgoingContractValidation` (default **true**);
para payloads de saida muito grandes (~2 MiB UTF-8 JSON estimados), a
validacao de saida e omitida para limitar CPU (o frame ainda respeita limites
negociados de tamanho).
- Tracer de mensagens Socket: com `enableSocketSummarizeLargePayloadLogs`
(default **true**), payloads acima de ~8 KiB UTF-8 estimados sao substituidos
por um resumo no callback (nao altera o fio).
- Implementacao: serializacao/deserializacao JSON UTF-8 acima de ~384 KiB pode
executar em isolate no envio (`prepareSendAsync`) e na recepcao
(`receiveProcessAsync`). Fingerprint de idempotencia (quando a flag esta
ativa) tambem pode ser calculado em isolate para `params` grandes.
- Estrategia atual recomendada: manter **JSON + GZIP** como baseline do
transporte, usando o modo outbound `auto` quando o emissor quiser preservar a
opcao de cair para `cmp: none` caso o bloco comprimido nao compense. Avaliar
codec binario real so se benchmark do pipeline mostrar gargalo concreto que
nao seja resolvido por shape de payload ou por `gzip`.
- Perfis operacionais recomendados para `outboundCompressionMode`:


| Perfil              | Configuracao | Quando usar                                                                  | Trade-off principal                                        |
| ------------------- | ------------ | ---------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Baixa latencia      | `none`       | Fluxos sensiveis a p95/p99, payload pequeno/medio, ou payload incompressivel | Menor CPU e menor latencia, com maior consumo de banda     |
| Balanceado (padrao) | `auto`       | Trafego misto em producao, com variacao de tamanho e compressibilidade       | Equilibra banda e CPU por mensagem (`cmp: gzip` ou `none`) |
| Economia de banda   | `gzip`       | Links limitados, respostas SQL grandes/repetitivas, custo de CPU aceitavel   | Reduz bytes no fio, com aumento de latencia/CPU            |


- Parametros atuais recomendados (com base em benchmark):
  - `compressionThreshold`: `4096`
  - `gzipIsolateThresholdBytes`: `32 * 1024` (32 KiB)
  - `jsonPayloadIsolateEncodeThresholdBytes`: `384 * 1024` (384 KiB)
- `ProtocolMetricsCollector` mantem janela rolante configuravel e resume
  latencia por media e percentis `p50`/`p95`/`p99` para total, encode,
  compressao, decode e descompressao. Use esses percentis para decidir entre
  `none`, `auto` e `gzip` em producao.
- A tela de logs WebSocket mostra um resumo de 15 minutos desses percentis,
bytes economizados, uso de isolates e erros por protocolo. Isso e diagnostico
local; nao altera o contrato no fio.
- Benchmark reproduzivel do pipeline:
  `dart run tool/benchmark_transport_pipeline.dart --iterations 20`.
  Use `--json` para exportar os resultados e `--threshold 4096` para comparar
  limiares.
- Respostas `rpc:response` muito grandes geram evento local
  `rpc:response:large_payload_advice` quando ainda nao ha streaming direto do
  banco, chunks e backpressure habilitados em conjunto. O evento e rate-limited
  e serve como recomendacao operacional para evitar materializacao de payloads
  grandes em memoria.
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

- Executa fluxo v2 completo (`agent:register` -> `rpc:request` -> `rpc:response`) usando `PayloadFrame`.
- Homologa encode/compress/decode/decompress no cliente.
- Trata erro JSON-RPC em vez de assumir sempre `result`.
- Homologa `sql.execute` com sucesso e com falha SQL.
- Homologa `sql.executeBatch` com itens de retorno.
- Confirma que o cliente rejeita eventos sem `PayloadFrame` (o agente nao aceita JSON cru em eventos de app; nao ha fallback para protocolo legado).

### Erros e retry

- Homologa erros de payload invalido (`-32009`) e decode (`-32010`).
- Homologa falha de frame/signature/descompressao (`-32011` e `invalid_signature`).
- Homologa falha de auth (`-32001`) e permissao (`-32002`).
- Valida regra de retry somente quando `retryable=true`.
- Exibe `user_message` ao usuario e registra `correlation_id` para suporte.
- Garante equivalencia de comportamento entre legado e v2 para mesmos cenarios.

### Autorizacao

- Envia `client_token` em `params` para toda request quando auth ativo.
- Trata `-32001` (missing/invalid token) e `-32002` (unauthorized).
- Valida que token revogado retorna `-32002` com `reason: token_revoked`.
- Homologa `client_token.getPolicy` com auth ativo (policy coerente com token).

### Contrato v2.1

- Inclui `api_version` e `meta` em requests (quando feature ativa).
- Valida que responses incluem `api_version` e `meta`.
- Trata notifications (request sem `id`) sem esperar response.
- Respeita limite de 32 itens por batch com IDs unicos.
- Valida schemas de params conforme schemas publicados.

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
- Schemas JSON de params por metodo (`sql.execute`, `sql.executeBatch`, `sql.cancel`, `agent.getProfile`).
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
sao validados antes do envio quando `enableSocketSchemaValidation` e
`enableSocketOutgoingContractValidation` estao ativos (com omissao de
validacao de saida acima do limiar de tamanho documentado nas limitacoes).
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

### Ajustes pos-v2.5 (readiness explicito e hints de backpressure)

- `agent:ready` adicionado como evento opcional apos `agent:capabilities`.
- `extensions.protocolReadyAck = true` passa a anunciar suporte ao ack explicito
de prontidao.
- `extensions.recommendedStreamPullWindowSize` e
`extensions.maxStreamPullWindowSize` passam a anunciar hints opcionais para o
hub ajustar `rpc:stream.pull`.

### `v2.7` (introspecao de client token policy)

- Metodo RPC `client_token.getPolicy` para retornar a politica resolvida
(`ClientTokenPolicy`) do token apresentado, sem executar SQL.
- Schemas JSON dedicados em `docs/communication/schemas/` para params e result.
- OpenRPC `info.version` alinhado a `2.7.0` e entrada do metodo em `methods`.

### `v2.8` (getPolicy endurecimento e metadata)

- Flag `enableClientTokenPolicyIntrospection` (default true) para desligar o
metodo sem desativar autorizacao SQL.
- Resultado com `token_id` / `issued_at` / `updated_at` quando aplicavel; `payload`
com redacao de chaves sensiveis na resposta RPC.
- Rate limit por agente+credential (`CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE`,
default 120) e teto de escopos distintos (`CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS`,
default 8192); erro `-32013` com `retry_after_ms` e `reset_at` em `error.data`.
- Redacao de `payload` com allowlist para chaves operacionais (`token_scope`, etc.).
- Metricas de dispatch para sucesso, falha agregada, falha por tipo de `Failure`, e rate limit.
- Toggle de introspecao em configuracao desktop (WebSocket / politica de client token).
- OpenRPC `info.version` `2.8.0`.

### `v2.9` (health introspection)

- Metodo RPC `agent.getHealth` para snapshot de saude do processo, pool ODBC,
fila SQL e metricas de queries.
- Schemas JSON dedicados em `docs/communication/schemas/` para params e result.
- OpenRPC `info.version` `2.9.0` e entrada do metodo em `methods`.
- `observer.*` permanece fora do contrato publicado ate existir implementacao,
schemas, OpenRPC e testes E2E.

### `v2.10` (bulk insert nativo)

- Metodo RPC `sql.bulkInsert` para cargas grandes via bulk insert nativo ODBC.
- Schemas JSON dedicados para params e result.
- OpenRPC `info.version` `2.10.0` e entrada do metodo em `methods`.

### `v2.11` / `v2.11.1` / `v2.11.2` (acoes do agente: execucao remota conservadora)

- Metodo RPC `agent.action.run` para enfileirar acao salva/aprovada no agente,
com `idempotency_key` obrigatoria, sem comando livre/ad-hoc e sem aguardar o
processo terminar.
- Metodo RPC `agent.action.validateRun` (`v2.11.1`) para preflight remoto com
as mesmas chaves obrigatorias que `run`, sem persistir execucao nem iniciar
processo; retorna resumo com `would_replay_existing_execution` quando aplicavel.
- Metodo RPC `agent.action.cancel` para cancelar execucao `queued`/`running`,
matando somente o processo principal quando aplicavel.
- Metodo RPC `agent.action.getExecution` para consulta remota de execucao de
acao salva no agente.
- Metodos protegidos por `enableRemoteAgentActions`; quando desativados, retornam
erro seguro sem expor historico.
- Quando auth por token esta ativa, os metodos usam scopes proprios de acoes
(`agent_actions.run`, `agent_actions.validate_run`, `agent_actions.cancel` e
`agent_actions.read_execution`) sem reaproveitar permissao SQL como atalho.
- Resultado e sempre redigido: nao retorna comando bruto, argumentos sensiveis
ou stack trace; expoe apenas identidade auxiliar segura, preview redigido,
status, timestamps, saida capturada ja redigida e failure acionavel.
- `v2.11.2` adiciona status terminal `skipped`, flags explicitas de skip por
concorrencia segura no snapshot remoto de execucao e contadores de health para
execucoes terminais `skipped`.
- Schemas JSON dedicados para params e result.
- OpenRPC `info.version` `2.11.2` e entradas dos metodos em `methods`.

### Alinhamento doc/codigo (pos-v2.5)

- Politica de reconnect do app documentada conforme `ConnectionProvider` /
`computeReconnectDelay` (base 5 s, teto 60 s, jitter).
- Assinatura invalida: `error.data.reason` = `invalid_signature` com codigo
`-32001` (inclui falha de assinatura do `PayloadFrame` na decodificacao).
- `rpc.discover`: fluxo no transporte, OpenRPC, e interacao com notifications
estritas.
- `agent.getProfile`: metodo RPC para consulta de cadastro atual do agente,
documentado no OpenRPC e retornado via `rpc:response`.
- Exemplo de `extensions` em capabilities alinhado ao default do agente.
- Tabela "Mapa rapido de eventos" corrigida em Markdown.
- Compressao outbound `none` / `gzip` / `auto` (politica local); fio apenas
`cmp: none` ou `cmp: gzip`; anuncio `compressions` conforme modo.
- `-32013`: janela de taxa (`RpcRequestGuard`) e limite de handlers concorrentes
(`maxConcurrentRpcHandlers`, default 32).
- Feature flags `enableSocketOutgoingContractValidation` e
`enableSocketSummarizeLargePayloadLogs`; isolate JSON ~384 KiB e fingerprint
de idempotencia para cargas grandes.

## Schemas JSON (contrato)

### Envelope

- `docs/communication/schemas/rpc.request.schema.json`
- `docs/communication/schemas/rpc.response.schema.json`
- `docs/communication/schemas/rpc.error.schema.json`
- `docs/communication/schemas/rpc.batch.request.schema.json`
- `docs/communication/schemas/rpc.batch.response.schema.json`
- `docs/communication/schemas/agent.register.schema.json`
- `docs/communication/schemas/agent.profile.schema.json`
- `docs/communication/schemas/agent.capabilities.schema.json`
- `docs/communication/schemas/agent.ready.schema.json`

### Params por metodo

- `docs/communication/schemas/rpc.params.sql-execute.schema.json`
- `docs/communication/schemas/rpc.params.sql-execute-batch.schema.json`
- `docs/communication/schemas/rpc.params.sql-bulk-insert.schema.json`
- `docs/communication/schemas/rpc.params.sql-cancel.schema.json`
- `docs/communication/schemas/rpc.params.agent-get-profile.schema.json`
- `docs/communication/schemas/rpc.params.agent-get-health.schema.json`
- `docs/communication/schemas/rpc.params.agent-action-run.schema.json`
- `docs/communication/schemas/rpc.params.agent-action-validate-run.schema.json`
- `docs/communication/schemas/rpc.params.agent-action-cancel.schema.json`
- `docs/communication/schemas/rpc.params.agent-action-get-execution.schema.json`
- `docs/communication/schemas/rpc.params.client-token-get-policy.schema.json`

### Result por metodo

- `docs/communication/schemas/rpc.result.sql-execute.schema.json`
- `docs/communication/schemas/rpc.result.sql-execute-batch.schema.json`
- `docs/communication/schemas/rpc.result.sql-bulk-insert.schema.json`
- `docs/communication/schemas/rpc.result.agent-get-profile.schema.json`
- `docs/communication/schemas/rpc.result.agent-get-health.schema.json`
- `docs/communication/schemas/rpc.result.agent-action-cancel.schema.json`
- `docs/communication/schemas/rpc.result.agent-action-validate-run.schema.json`
- `docs/communication/schemas/rpc.result.agent-action-get-execution.schema.json`
- `docs/communication/schemas/rpc.result.client-token-get-policy.schema.json`

### Streaming

- `docs/communication/schemas/rpc.stream.chunk.schema.json`
- `docs/communication/schemas/rpc.stream.complete.schema.json`
- `docs/communication/schemas/rpc.stream.pull.schema.json`

### Frame fisico (PayloadFrame)

- `docs/communication/schemas/payload-frame.schema.json`

### OpenRPC

- `docs/communication/openrpc.json`

### Fixtures de contrato (JSON-RPC)

- Amostras de fio para `agent.action.run`, `validateRun`, `cancel`, `getExecution`
  e erro remoto desligado: `test/fixtures/rpc/rpc_request_agent_action_*.json`,
  `test/fixtures/rpc/rpc_response_agent_action_*.json`.
- Validacao contra os schemas publicados: rode
  `flutter test test/docs/communication/contract_fixtures_test.dart` (envelope
  `rpc.request` / `rpc.response`, blocos `params` / `result` por schema de metodo
  e objeto `error` vs `rpc.error` quando presente).

## Referencias internas

- Modelos RPC: `lib/domain/protocol/`
- Dispatcher RPC: `lib/application/rpc/rpc_method_dispatcher.dart`
- Transporte: `lib/infrastructure/external_services/socket_io_transport_client_v2.dart`
- Negociacao: `lib/application/services/protocol_negotiator.dart`
- Guia de cliente: `docs/communication/socketio_client_binary_transport.md`
- Evolucao pendente: `docs/communication/socket_communication_roadmap.md`
