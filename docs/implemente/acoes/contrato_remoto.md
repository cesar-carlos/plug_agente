# Contrato remoto — agent.action.* (Plug Agente)

Indice focado em Socket.IO / JSON-RPC para acoes agendadas. A fonte canonica
completa continua em
[plano_acoes_agendadas_execucoes.md](../plano_acoes_agendadas_execucoes.md)
(Fase 6, Test Plan, Riscos aceitos).

**Status oficial (2026-05-21):** contrato e roteamento no agente estao
**fechados para local/CI**; rollout de producao continua dependente de `COM`
real aprovado (RA-01), policy fina no Hub/consumidor (RA-02) e live E2E
assinado contra Hub real (RA-05).

## Metodos publicados

| Metodo | Side effect | Batch MVP | Idempotencia |
| --- | --- | --- | --- |
| `agent.action.run` | Sim (enfileira execucao) | Rejeitado | `idempotency_key` obrigatorio (remoto) |
| `agent.action.validateRun` | Nao | Permitido (com limite) | Opcional (cache RPC) |
| `agent.action.cancel` | Sim (cancelamento) | Rejeitado | — |
| `agent.action.getExecution` | Nao (leitura redigida) | Permitido (com limite) | — |

Constantes: `lib/core/constants/agent_action_rpc_constants.dart`.

Transporte: apenas `rpc:request` / `rpc:response` dentro de `PayloadFrame` —
sem evento Socket.IO paralelo.

## Handshake e capability

1. Hub conecta e completa `agent:register` / `agent:capabilities` (e `agent:ready`
   quando negociado).
2. Com `enableRemoteAgentActions=true`, o agente anuncia
   `extensions.agentActions` via `AgentActionsRemoteCapabilityBuilder`.
3. Metodos so executam apos roteamento em `RpcMethodDispatcher` com gates:
   feature flag, manutencao, `AgentActionRuntimeStateGuard`, scopes/allowlist
   (`AgentActionRemoteAuthorizationService`), rate limit
   (`AgentActionRemoteRateLimiter`).

Scopes canonicos: `agent_actions.run`, `agent_actions.validate_run`,
`agent_actions.cancel`, `agent_actions.read_execution` (e wildcard
`agent_actions.*`). Policy no token: bloco `payload.agent_actions` (+ aliases
legados).

## Autorizacao e erros

- Autorizacao de acoes e **separada** de SQL; nao reutilizar deny de tabela como
  permissao de comando.
- Falhas `Action*` no wire: `category: action` + `reason` estavel
  (`FailureToRpcErrorMapper`).
- Codigos MVP: faixa compartilhada `-32001`..`-32015`, `-32602`; reservado
  `-32299`..`-32200` para codigos dedicados futuros.
- Contexto remoto inline: **rejeitado** no MVP (`supportsContext: false`, RA-03).

## Schemas e OpenRPC

Fonte de verdade:

- `docs/communication/openrpc.json`
- `docs/communication/schemas/rpc.params.agent-action-*.schema.json`
- `docs/communication/schemas/rpc.result.agent-action-*.schema.json`
- `docs/communication/socket_communication_standard.md`

Testes de contrato:

- `test/docs/openrpc_contract_test.dart`
- `test/docs/communication/contract_fixtures_test.dart`
- Fixtures: `test/fixtures/rpc/rpc_*_agent_action_*.json`

## Implementacao no agente

| Componente | Caminho |
| --- | --- |
| Dispatcher | `lib/application/rpc/rpc_method_dispatcher.dart` |
| Batch / notification | `lib/infrastructure/external_services/transport/rpc_inbound_handler.dart` |
| Run / validate / cancel / get | use cases em `lib/application/use_cases/` |
| Auditoria append-only | Drift `agent_action_remote_audit` + `RpcMethodDispatcher` |
| Output paging remoto | `lib/application/rpc/agent_action_execution_output_pager.dart` |
| Capability builder | `lib/application/actions/agent_actions_remote_capability_builder.dart` |

Teste de roteamento: `test/application/rpc/rpc_method_dispatcher_agent_action_test.dart`.

## Validacao local / CI

```powershell
.\tool\run_agent_actions_operational_gate.ps1
```

Manifesto: `tool/agent_actions_contract_test_paths.txt`.

## Live Hub (opt-in)

Variaveis: ver plano **Roteiro operacional pos-MVP** e `docs/testing/e2e_setup.md`.

```powershell
dart run tool/validate_live_hub_agent_actions_env.dart
.\tool\homologate_hub_agent_actions.ps1 -PrepareLiveEnv
.\tool\homologate_hub_agent_actions.ps1 -ValidateLiveEnv -RunLiveTests
```

Teste: `test/integration/hub_agent_action_rpc_live_e2e_test.dart` (tag `live`).

**Avisos comuns:** JWT expirado (`fetch_e2e_hub_token_from_local_config.dart
--apply-token --force` ou credenciais no `.env`); par HMAC `e2e-dev` vs Hub
remoto (copiar `PAYLOAD_SIGNING_*` do servidor Hub ou
`promote_e2e_signing_from_monorepo_env.dart` quando `plug_server/.env` existir).

Ver tambem [`seguranca_acoes.md`](seguranca_acoes.md) (live Hub, flags, RA).

## Pendente cross-repo / producao

| ID | Item |
| --- | --- |
| RA-01 | Registrar o primeiro handler `COM` real aprovado; sem isso `comObject` segue homologacao/stub |
| RA-02 | Allowlist fina e rate limit no **consumidor Hub**; bridge/validator deve aceitar os metodos publicados sem afrouxar o contrato |
| RA-03 | Contexto remoto inline no RPC (quando produto aceitar) |
| RA-05 | Homologacao live com Hub real emitindo `agent.action.*` apos ready |

## Subdocs relacionados (planejados)

- `runner_local.md`, `runner_elevado.md`, `ui_acoes.md`, `seguranca_acoes.md`,
  `tipos_de_acao.md` — ainda no plano mestre ate necessidade de fatiar.
