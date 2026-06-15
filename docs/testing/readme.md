# Testing

Guias de configuracao e estrategia para testes E2E, integracao e
concorrencia. Os testes unitarios e widget tests seguem as regras gerais em
`.cursor/rules/testing.mdc` e `.cursor/rules/testing_dart_flutter.mdc`.

| Arquivo | Quando consultar |
| --- | --- |
| [e2e_setup.md](e2e_setup.md) | Indice central: pre-requisitos, preflight e como rodar |
| [e2e_api.md](e2e_api.md) | Testes E2E da API HTTP (`api_test.dart`) |
| [e2e_hub.md](e2e_hub.md) | Hub Socket.IO smoke + `PayloadFrame` assinado + contrato `agent.action.*` live |
| [e2e_actions.md](e2e_actions.md) | Acoes locais: stub COM, retencao, runner elevado Windows |
| [e2e_odbc.md](e2e_odbc.md) | Testes ODBC (streaming, RPC, DML perf, bulk load, queue burst, lock contention) |
| [sql_queue_concurrency_tests.md](sql_queue_concurrency_tests.md) | Estrategia de testes para `SqlExecutionQueue` + `QueuedDatabaseGateway` + burst tests |
| [single_instance_multiuser.md](single_instance_multiuser.md) | Cenarios manuais de instancia unica em multi-usuario Windows |

## Testes que envolvem recursos reais

- Sao **opt-in** via variaveis de ambiente (`RUN_LIVE_*`,
  `RUN_ODBC_*`, `ODBC_E2E_*`, etc.).
- O helper canonico para acessar variaveis e
  `test/helpers/e2e_env.dart` (`E2EEnv`).
- Sem variaveis, os testes sao `skip` com mensagem clara.

## Atalhos operacionais (Windows)

- `tool/e2e/check_e2e_env.dart` — preflight de `.env`.
- `tool/e2e/validate_live_hub_agent_actions_env.dart` — preflight live hub.
- `python tool/odbc/run_odbc_operational_validation.py` — preflight + worksheet ODBC.
- `python tool/agent_actions/run_agent_actions_operational_gate.py` — gate local/CI sem hub.
- `python tool/agent_actions/homologate_hub_agent_actions.py` — homologacao live opt-in.
