# Testing

Guias de configuracao e estrategia para testes E2E, integracao e
concorrencia. Unitarios e widget tests: `.cursor/rules/testing.mdc` e
`.cursor/rules/testing_dart_flutter.mdc`.

## E2E

Indice central (pre-requisitos, preflight, como rodar, familias):
[e2e_setup.md](e2e_setup.md).

## Outros

| Arquivo | Quando consultar |
| --- | --- |
| [sql_queue_concurrency_tests.md](sql_queue_concurrency_tests.md) | Estrategia de testes para `SqlExecutionQueue` + `QueuedDatabaseGateway` |
| [single_instance_multiuser.md](single_instance_multiuser.md) | Cenarios manuais de instancia unica em multi-usuario Windows |

## Opt-in

Testes com API/ODBC/Hub reais sao opt-in via `RUN_LIVE_*` / `RUN_ODBC_*` /
`ODBC_E2E_*`. Helper: `test/helpers/e2e_env.dart` (`E2EEnv`). Sem variaveis →
`skip` com mensagem clara.

Atalhos: `dart run tool/e2e/check_e2e_env.dart`,
`python tool/agent_actions/run_agent_actions_operational_gate.py`,
`python tool/odbc/run_odbc_operational_validation.py`.
