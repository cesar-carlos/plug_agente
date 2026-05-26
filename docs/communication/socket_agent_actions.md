# Plug JSON-RPC - `agent.action.*` (Implemented)

Detalhamento dos metodos JSON-RPC para acoes agendadas/remotas. Este
documento e parte do contrato canonico — as regras gerais de envelope, batch,
streaming, autenticacao, transporte e signing continuam em
[`socket_communication_standard.md`](socket_communication_standard.md).

Todos os metodos abaixo dependem da feature flag
`enableRemoteAgentActions`. Quando desligada, qualquer metodo `agent.action.*`
responde `-32002` com `reason` `agent_actions_remote_disabled`.

Implementacao no agente: `lib/application/rpc/rpc_method_dispatcher.dart` +
use cases em `lib/application/use_cases/`. Tabela de auditoria append-only:
Drift `agent_action_remote_audit`. Capability:
`AgentActionsRemoteCapabilityBuilder`.

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
