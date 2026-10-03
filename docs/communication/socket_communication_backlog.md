# Socket Communication Backlog (Execution Plan)

## Objetivo

Este backlog lista apenas itens pendentes de evolucao do protocolo Socket.IO /
Plug JSON-RPC.

- Estado implementado atual:
  `docs/communication/socket_communication_standard.md`
- Historico de itens entregues:
  `docs/communication/socket_communication_roadmap.md`

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
  outbound ainda no-op ate Decisao 3 / consumo no hub
  (`docs/implemente/plano_auto_update_evolution.md`). **Nao** publicado em
  `openrpc.json` / `rpc.discover` ate o hub aceitar o metodo.
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
