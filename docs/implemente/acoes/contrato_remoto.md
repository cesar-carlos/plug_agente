# Contrato remoto — agent.action.* (Plug Agente)

Entry-point para Socket.IO / JSON-RPC de acoes. **Nao duplica** o contrato wire.

**Status (2026-05-21):** roteamento no agente fechado para local/CI; producao
depende de RA-01 / RA-02 / RA-05.

## Fontes de verdade

| Assunto | Documento |
| --- | --- |
| Metodos, params, results, policy, auditoria | [`socket_agent_actions.md`](../../communication/socket_agent_actions.md) |
| Schemas + OpenRPC | [`openrpc.json`](../../communication/openrpc.json), [`schemas/`](../../communication/schemas/) |
| Status / backlog RA / riscos | [`plano_acoes_agendadas_execucoes.md`](../plano_acoes_agendadas_execucoes.md) |
| Flags, rollback, live Hub | [`seguranca_acoes.md`](seguranca_acoes.md) |
| UI | [`ui_acoes.md`](ui_acoes.md) |
| Historico MVP | [`plano_acoes_mvp_2026-05.md`](../../archive/plano_acoes_mvp_2026-05.md) |

## Metodos (resumo)

| Metodo | Side effect | Nota |
| --- | --- | --- |
| `agent.action.run` | Sim | `idempotency_key` obrigatorio |
| `agent.action.validateRun` | Nao | Preflight sem persistir/iniciar |
| `agent.action.cancel` | Sim | Fila ou processo principal |
| `agent.action.getExecution` | Nao | Leitura redigida |

Constantes: `lib/core/constants/agent_action_rpc_constants.dart`.
Transporte: so `rpc:request` / `rpc:response` em `PayloadFrame`.

## Implementacao (paths)

| Componente | Caminho |
| --- | --- |
| Registry de handlers | `lib/application/rpc/handlers/rpc_method_handlers.dart` |
| Operacoes RPC | `lib/application/rpc/agent_action_rpc_method_handler_operations.dart` |
| Capability | `lib/application/actions/agent_actions_remote_capability_builder.dart` |
| Failure mapper | `lib/application/mappers/failure_to_rpc_error_mapper.dart` |
| Use cases run/validate/cancel/get | `lib/application/use_cases/` |

Teste de roteamento: `test/application/rpc/rpc_method_dispatcher_agent_action_test.dart`.
Fixtures: `test/fixtures/rpc/rpc_*_agent_action_*.json`.

## Validacao

```powershell
python tool/agent_actions/run_agent_actions_operational_gate.py
dart run tool/e2e/validate_live_hub_agent_actions_env.dart
python tool/agent_actions/homologate_hub_agent_actions.py --validate-live-env --run-live-tests
```

Live Hub: [`e2e_hub.md`](../../testing/e2e_hub.md).
