# Benchmark

Pasta genérica para **artefatos e documentação** de benchmark. O histórico de
timings gerado pelos testes E2E fica aqui por padrão; arquivos de dados locais
(`.jsonl`, etc.) continuam fora do Git — veja `.gitignore`.

## Objetivo

Medir a **latência de caminhos reais** do produto (ODBC + `RpcMethodDispatcher` +
`sql.execute` / `sql.executeBatch`) e **guardar séries temporais** para comparar
commits, drivers e máquinas ao longo do tempo.

Isso **não substitui** `flutter test --coverage` nem micro-benchmarks isolados:
é E2E com banco verdadeiro, portanto inclui rede/driver/pool e varia com o
ambiente.

## Modo Flutter e comparabilidade

Os testes rodam normalmente em **debug** (default do `flutter test`). Para
comparar números entre máquinas ou ao longo do tempo com menos ruído do JIT:

- `flutter test` — aceitável para tendência grosseira.
- `flutter test --release` — onde suportado, reduz overhead de asserções/assert.
- `flutter test --profile` — meio-termo.

O campo `build_mode` no JSONL vale `debug`, `profile` ou `release` para filtrar
séries que não devem misturar-se.

## Estratégia

1. **Opt-in** — benchmarks não rodam na suíte “live” comum; evita ruído e tempo
   extra no CI local.
2. **Mesmo stack dos E2E ODBC** — mesma mesa temporária, mesmo harness e DSNs da
   matriz (`primary`, `sql_server`, `postgresql` quando configurados).
3. **Warm-up + amostras** — descarta execuções iniciais e grava várias medições
   em ms: `mean_ms`, `min_ms`, `max_ms`, `median_ms`, `p90_ms`, `p95_ms`,
   `trimmed_mean_ms` (média sem um min e um max), `samples_ms`.
4. **Histórico append-only (JSONL)** — cada linha é um JSON; `run_id` (UUID) é
   **o mesmo** para todos os `target_label` da mesma execução de `flutter test`,
   o que agrupa primary / sql_server / postgresql num único “run”.
5. **Metadados** — Git, SO, Dart, `build_mode`, `database_hosting` opcional,
   contadores do `MetricsCollector`.

## Como rodar

Pré-requisitos: `.env` com DSN como nos outros testes em `test/live/` (ver
`docs/testing/e2e_setup.md` e `.env.example`).

| Variável                         | Função                                                                                                                |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `ODBC_E2E_BENCHMARK=true`        | Habilita `odbc_rpc_benchmark_live_e2e_test.dart`.                                                                     |
| `ODBC_E2E_BENCHMARK_RECORD=true` | Anexa uma linha JSON por DSN ao histórico.                                                                            |
| `ODBC_E2E_BENCHMARK_FILE`        | Caminho opcional do JSONL (padrão: `benchmark/e2e_odbc_rpc.jsonl`).                                                   |
| `ODBC_E2E_BENCHMARK_DB_HOSTING`  | `local` ou `remote` — contexto para gráficos (opcional).                                                              |
| `ODBC_E2E_BENCHMARK_MAX_MS_*`    | Limites opcionais de regressão (ms); ver tabela abaixo.                                                               |
| `ODBC_E2E_REQUIRE_MULTI_RESULT`  | Se `true`, o **benchmark** também falha quando `last_has_payload` é false no caso multi-result (alinhado ao E2E RPC). |

**Limites de regressão** (falham o teste se excedidos). Comparado com `median_ms`
dos casos com amostras; `rpc_sql_execute_multi_result` usa a mediana das
iterações.

| Sufixo env     | Chave em `cases`               |
| -------------- | ------------------------------ |
| `MATERIALIZED` | `rpc_sql_execute_materialized` |
| `BATCH_READS`  | `rpc_sql_execute_batch_reads`  |
| `NAMED_PARAMS` | `rpc_sql_execute_named_params` |
| `MULTI_RESULT` | `rpc_sql_execute_multi_result` |
| `BATCH_TX`     | `rpc_sql_execute_batch_tx`     |
| `STREAMING`    | `rpc_sql_execute_streaming`    |

Exemplo: `ODBC_E2E_BENCHMARK_MAX_MS_MATERIALIZED=800`.

Exemplos:

```bash
flutter test test/live/odbc_rpc_benchmark_live_e2e_test.dart
```

```bash
flutter test --tags benchmark
```

Resumo rápido do histórico:

```bash
dart run tool/summarize_e2e_benchmark.dart
dart run tool/summarize_e2e_benchmark.dart path/to/out.jsonl
```

A tag `benchmark` está em `dart_test.yaml` junto com `live`.

## O que é medido

Implementação: `test/live/odbc_rpc_benchmark_live_e2e_test.dart` e
`test/helpers/e2e_benchmark_recorder.dart`.

| Chave em `cases`               | Descrição resumida                                      |
| ------------------------------ | ------------------------------------------------------- |
| `rpc_sql_execute_materialized` | `sql.execute` SELECT materializado.                     |
| `rpc_sql_execute_batch_reads`  | `sql.executeBatch` com três SELECTs.                    |
| `rpc_sql_execute_named_params` | `sql.execute` com `params`.                             |
| `rpc_sql_execute_multi_result` | `multi_result` (várias iterações) + `last_has_payload`. |
| `rpc_sql_execute_batch_tx`     | `sql.executeBatch` com `transaction: true`.             |
| `rpc_sql_execute_streaming`    | `sql.execute` com stream (chunk size 1).                |

## Esquema JSONL (`schema_version`)

- **2** (atual): `run_id`, `build_mode`, `database_hosting?`, `cases` com
  `p90_ms` / `trimmed_mean_ms` nos blocos de stats, casos `batch_tx` e
  `streaming`.
- **1** (legado): linhas antigas sem esses campos — ferramentas devem tolerar.

## Interpretação

- Compare o mesmo `target_label`, `build_mode` e hardware quando possível.
- Tendência: `median_ms`, `p90_ms` ou `p95_ms` ao longo de `recorded_at` / `git_revision`; `max_ms` marca outliers num run.
- Agrupe por `run_id` para ver os três DSNs da mesma execução.
- `multi_result` com `last_has_payload: false` pode ser válido em alguns
  drivers; alinhar com `ODBC_E2E_REQUIRE_MULTI_RESULT` nos E2E funcionais.

## CI opcional

Workflow manual: `.github/workflows/e2e_benchmark_optional.yml` (`workflow_dispatch`).
Exige secrets de DSN no repositório e publica o JSONL como artifact quando o
ficheiro existir.

## Testes unitários (cobertura sem ODBC)

| Área                                       | Ficheiros                                         |
| ------------------------------------------ | ------------------------------------------------- |
| Stats / JSONL / paths                      | `test/helpers/e2e_benchmark_recorder_test.dart`   |
| Limites `MAX_MS`                           | `test/helpers/e2e_benchmark_assertions_test.dart` |
| Variáveis `E2EEnv` (benchmark)             | `test/helpers/e2e_env_benchmark_test.dart`        |
| Resumo JSONL (lógica partilhada com o CLI) | `test/tool/e2e_benchmark_summary_test.dart`       |
| Filtro LCOV por prefixo de caminho         | `test/tool/lcov_path_filter_test.dart`            |

A lógica do `dart run tool/summarize_e2e_benchmark.dart` está em
`tool/e2e_benchmark_summary.dart` para ser testada sem I/O.

### Cobertura Dart (sem API live)

- `tool/flutter_test_no_api.bat` / `tool/flutter_test_no_api.sh` — `flutter test --exclude-tags=live`.
- `tool/flutter_test_coverage_multi_result.bat` / `.sh` — `--coverage` + `coverage/lcov_multi_result.info` filtrado para `lib/application/rpc/` e `odbc_*` (ver `docs/testing/e2e_setup.md`).

## Versionamento

- **Versionado:** este `README.md` (e `.gitignore` da pasta).
- **Ignorado:** ficheiros de dados gerados (ex.: `*.jsonl`), salvo altere o
  `.gitignore` ou `ODBC_E2E_BENCHMARK_FILE`.
