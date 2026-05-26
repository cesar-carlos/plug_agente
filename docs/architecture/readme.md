# Architecture

Documentos sobre arquitetura de execucao, performance e confiabilidade do
agente. Foco no eixo ODBC + fila SQL + circuit breaker + observabilidade.

| Arquivo | Quando consultar |
| --- | --- |
| [QUICKSTART.md](QUICKSTART.md) | Tuning operacional rapido (`.env`), verificar logs e snapshots de health, troubleshooting de fila/pool/circuit breaker. |
| [performance_reliability_improvements.md](performance_reliability_improvements.md) | Estado tecnico atual do eixo ODBC: tuning, runtime, observabilidade, encoding. |
| [odbc_worker_evaluation_criteria.md](odbc_worker_evaluation_criteria.md) | Quando ajustar `ODBC_ASYNC_*`, criterios para benchmark e por que multi-`ServiceLocator` ainda esta fora de escopo. |
| [odbc_operational_validation_runbook.md](odbc_operational_validation_runbook.md) | Validacao operacional pos-deploy: smoke, burst, benchmark e snapshots de health. |

## Cross-references

- Testes E2E e DSN: `docs/testing/e2e_setup.md` (e familias relacionadas).
- Concorrencia da fila SQL: `docs/testing/sql_queue_concurrency_tests.md`.
- Wrappers operacionais Windows: `tool/run_odbc_operational_validation.ps1`,
  `tool/odbc_async_benchmark.ps1`, `tool/odbc_streaming_benchmark.ps1`,
  `tool/odbc_driver_matrix_benchmark.ps1`.
