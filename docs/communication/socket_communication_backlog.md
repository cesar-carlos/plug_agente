# Socket Communication Backlog (Execution Plan)

## Objetivo

Este backlog lista apenas itens pendentes de evolucao do protocolo Socket.IO /
Plug JSON-RPC.

- Estado implementado atual:
  `docs/communication/socket_communication_standard.md`
- Historico de itens entregues:
  `docs/communication/socket_communication_roadmap.md`

## Politica futura: execution_mode em sql.executeBatch

- Em v2.5, `sql.executeBatch` nao suporta `execution_mode`; todos os comandos rodam
em modo managed implicito.
- Opcoes para evolucao futura: (A) manter assim; (B) adicionar
`options.execution_mode` no batch (aplicado a todos os comandos); (C) adicionar
`commands[*].execution_mode` por comando.
- Decisao a ser tomada quando houver demanda ou requisito de passthrough por
comando.

## Proximos itens (quando priorizado)

- Spec RPC `agent.autoUpdate.diagnostics.push` — schema agente entregue
  (`docs/communication/schemas/auto_update_diagnostics.schema.json`); transport
  outbound ainda no-op ate Decisao 3 / consumo no hub
  (`docs/implemente/plano_auto_update_evolution.md`). **Nao** publicado em
  `openrpc.json` / `rpc.discover` ate o hub aceitar o metodo.
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
