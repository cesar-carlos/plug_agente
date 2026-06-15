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
- Layer boundaries (CI): `test/architecture/layer_boundaries_test.dart` — garante
  que `domain`/`application` nao importam `infrastructure` e que o dispatcher RPC
  permanece facade fina.
- Sql RPC modularization (maintainers): handlers em `lib/application/rpc/`
  (`sql_execute_handler.dart`, `sql_batch_handler.dart`, etc.); ponto de entrada
  `sql_rpc_method_handler_operations.dart`. Mapa resumido em
  `docs/project_overview.md` (secao Sql RPC).
- Wrappers operacionais: `python tool/odbc/run_odbc_operational_validation.py`,
  `python tool/benchmarks/odbc_async_benchmark.py`, `python tool/benchmarks/odbc_streaming_benchmark.py`,
  `python tool/benchmarks/odbc_driver_matrix_benchmark.py`.
