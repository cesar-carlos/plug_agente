# Socket Communication Backlog (Execution Plan)

## Objetivo

Este backlog lista apenas itens pendentes de evolucao do protocolo Socket.IO /
Plug JSON-RPC.

- Estado implementado atual:
  `docs/communication/socket_communication_standard.md`
- Historico de itens entregues:
  `docs/communication/socket_communication_roadmap.md`

## Contract review findings (2026-10-24)

The documentation review at `eb1888b4` found the following implementation/schema
boundaries. Updating prose does not resolve runtime defects or authorize release.

### Resolved: compact errors losing correlation

The review reproduced compact source/operation errors being replaced by
`-32603`, `id: null` under outgoing schema validation. The three handlers now use
`RpcErrorCode.buildErrorData`, preserving the RPC ID, safe `failure_code` and
`retryable: false`. The schema and outgoing validation remain unchanged.

Regression coverage exercises all five methods with string/numeric IDs, mixed
batches with a successful sibling, invalid operation parameters, domain failures
and unexpected exceptions through the real loaded schemas and response preparer.
Request metadata and safe correlation survive; exception details remain private.
Unknown SQL-operation outcomes still require reconciliation rather than replay.

### Published shapes and procedural validation differ

- `sql.describeSchema`: schema requires `offset` and `pageSize`; the domain reader
  supplies defaults. Clients must send both until a deliberate contract change.
  The reader additionally rejects duplicate resources, offsets outside the scope,
  unsafe database names and unsupported dialects, which schema validation alone
  cannot establish.
- Source/operation schemas retain `firebird` in some enums, but the current
  `ExpectedSource` parser only accepts `postgres`, `mssql`, `sybase`. Preserve
  the historical wire enums pending coordinated compatibility decisions; never
  advertise runtime Firebird support from schema acceptance alone.
- JSON Schema `maxLength` counts characters, while operation SQL/plan readers
  apply UTF-8 byte caps and additional bounds, binding and statement rules.
  Schema acceptance alone is not execution admission.
- A failed schema load currently skips that schema in
  `JsonSchemaContractValidator`; procedural checks continue. Review fail-closed
  behavior and add coverage for missing/failed contract assets before claiming
  complete runtime schema enforcement.

### Acceptance scope

The existing contract/transport test selection passed (295 tests), and focused
checks confirmed the error-shape defect, six-parameter parser support and the
incomplete documentation response examples (now corrected). A second selection
covering documentation, runtime validators, health and source metadata passed
236 tests, including the focused checks; the selections overlap. These are local
checks, not real hub/driver/installation homologation. Required next coverage
includes live extension denial through outgoing framing, schema-vs-reader boundary
cases and the current three-engine coordinated release matrix.

## Politica futura: execution_mode em sql.executeBatch

- In the current profile (**2.11.2**), `sql.executeBatch` still does not support
`execution_mode`; commands use implicit managed mode.
- Opcoes para evolucao futura: (A) manter assim; (B) adicionar
`options.execution_mode` no batch (aplicado a todos os comandos); (C) adicionar
`commands[*].execution_mode` por comando.
- Decisao a ser tomada quando houver demanda ou requisito de passthrough por
comando.

## Proximos itens (quando priorizado)

- Communication lifecycle fixes and hub columnar normalization are implemented
  without changing profile 2.11.2. Deployment validation remains separate:
  run real ODBC fixtures and equal 15-minute staging windows; stop promotion on
  contract regressions, loss/duplication, errors/timeouts or retained state.
- Benchmark evidence must distinguish codec microbenchmarks, loopback transport,
  the production Dart transport with a deterministic gateway, and real ODBC.
  Use the same harness/configuration and nine repetitions for base/candidate;
  newly accepted columnar cases have correctness/capacity gates, not a speedup
  percentage against previously rejected frames.

- Spec RPC `agent.autoUpdate.diagnostics.push` — schema agente entregue
  (`docs/communication/schemas/auto_update_diagnostics.schema.json`); transport
  outbound ainda no-op. Proposta fora do plano vigente do servico de update;
  requer contrato e consumo aprovados separadamente no hub. **Nao** publicado
  em `openrpc.json` / `rpc.discover` ate o hub aceitar o metodo.
- Canal socket `agent:profile.update` / `agent:profile.updated` no runtime do
  agente (hoje o sync de perfil usa apenas REST
  `PATCH /api/v1/agents/{agentId}/profile`; o hub ja expoe o canal socket).
- Hint de UI dedicado para `agent:session.superseded` / `session_active`
  (runtime ja classifica e recupera; mensagem ao utilizador ainda generica).
- Homologacao E2E hub-agente para `client_token.getPolicy` (rate limit, `retry_after_ms` / `reset_at`).
- Teste de carga do limitador com muitos escopos distintos (`CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS`).
- Homologacao do guia de cliente para encode/compress/decode/decompress.
- Testes de integracao end-to-end para limites negociados e assinatura.
- Rotacao automatica de chaves de assinatura sem downtime.
- Monitoramento/alertas de payload signing failures.

## Regra de manutencao deste backlog

- Registrar apenas itens ainda pendentes.
- Nao reintroduzir itens concluidos; ao concluir, mover para o roadmap historico
  e atualizar `socket_communication_standard.md`.
