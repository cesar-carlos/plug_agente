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
| `sql.cancel` | planned |
| Streaming chunked | planned |
| Backpressure | planned |
| Notification JSON-RPC (sem resposta) | planned |
| Regras estritas de batch (IDs unicos/ordem) | planned |
| Garantia de entrega por evento (ack/retry) | planned |
| Connection state recovery | implemented (agent-side retry/backoff) |
| Politica de auth no reconnect | implemented (agent-side) |
| Rate limiting por evento | implemented (agent-side) |
| Schema JSON oficial de contrato | planned |
| Validacao criptografica de token (JWKS) | planned |
| Revogacao em sessao ativa | planned |
| Paridade de enforcement no legado | implemented |
| Observabilidade de autorizacao (collector allow/deny) | implemented |
| Logs de decisao de autorizacao no transporte (`AUTH`) | implemented |
| Resumo de autorizacao no dashboard (`WebSocketLogViewer`) | implemented |
| Refresh de auth em runtime (`token_revoked`/`authentication_failed`) | implemented |
| Heartbeat de sessao (`agent:heartbeat`/`hub:heartbeat_ack`) | implemented (agent-side) |
| Recovery de conexao curta com retry/backoff | implemented (agent-side) |
| Replay protection por janela de request ID | implemented (agent-side) |
| Auditoria de token management | planned |

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

- UI deve mostrar apenas `user_message` e, opcionalmente, `correlation_id`.
- UI nao deve exibir stack trace ou detalhes de infraestrutura ao usuario final.
- Logs tecnicos devem registrar `technical_message`, `code`, `reason`,
  `category`, `correlation_id`.
- Retry automatico so deve ocorrer quando `retryable=true`.

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
  "payload": {
    "sql": "SELECT * FROM users"
  }
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
- Payload unico por request/response (sem chunking ativo).
- Limites finos por transporte ainda nao sao negociados no contrato atual.

## Limitacoes do estado atual

- Nao ha metodo RPC oficial de cancelamento (`sql.cancel`) ativo.
- Nao ha streaming chunked ativo para resultados grandes.
- Backpressure nao esta definido no contrato atual.
- Campos obrigatorios extras como `api_version`/`meta` ainda nao fazem parte
  do contrato ativo.
- Notification JSON-RPC (sem `id`) nao esta formalizada por contrato.
- Regras estritas de batch (ordem de resposta e IDs duplicados) nao estao
  formalizadas.
- Garantia de entrega por tipo de evento (ack/retry) nao esta formalizada.
- Connection state recovery e replay por offset nao estao ativos.
- Politica de refresh/auth no reconnect nao esta formalizada no contrato.
- Rate limits/quotas por evento nao estao contratualmente definidos.
- Nao ha JSON Schema oficial publicado para validacao de payload.
- Validacao criptografica de token (issuer/audience/kid/alg) nao esta
  formalizada no contrato.
- Revogacao de token com efeito em sessao ativa nao esta formalizada.
- Trilha de auditoria para token management nao esta definida.

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

## Referencias internas

- Modelos RPC: `lib/domain/protocol/`
- Dispatcher RPC: `lib/application/rpc/rpc_method_dispatcher.dart`
- Transporte: `lib/infrastructure/external_services/socket_io_transport_client_v2.dart`
- Negociacao: `lib/application/services/protocol_negotiator.dart`
- Evolucao planejada: `docs/communication/socket_communication_roadmap.md`





