# Benchmark

This folder stores benchmark documentation and local benchmark artifacts
(`.jsonl`). Data files are ignored by git.

## Suites

### 1) ODBC RPC live benchmark

- Test: `test/live/odbc_rpc_benchmark_live_e2e_test.dart`
- Gate: `ODBC_E2E_BENCHMARK=true`
- Optional record: `ODBC_E2E_BENCHMARK_RECORD=true`
- Default output: `benchmark/e2e_odbc_rpc.jsonl`

Main case keys:

- `rpc_sql_execute_materialized`
- `rpc_sql_execute_batch_reads`
- `rpc_sql_execute_named_params`
- `rpc_sql_execute_multi_result`
- `rpc_sql_execute_batch_tx`
- `rpc_sql_execute_write_dml`
- `rpc_sql_execute_timeout_cancel`
- `rpc_sql_execute_streaming`
- `rpc_sql_execute_streaming_chunks`
- `rpc_sql_execute_materialized_parallel`
- `rpc_sql_execute_batch_reads_parallel`
- `rpc_sql_execute_multi_result_parallel`
- `rpc_sql_execute_write_dml_parallel`

Each case includes latency stats (`mean_ms`, `median_ms`, `p90_ms`, `p95_ms`,
`trimmed_mean_ms`, `samples_ms`) and stage-level p95 derived from metrics
collector samples (`stage_latency_p95_ms`).

### 2) Socket transport codec benchmark

- Test: `test/infrastructure/codecs/transport_pipeline_benchmark_test.dart`
- Gate: `SOCKET_TRANSPORT_BENCHMARK=true`
- Optional record: `SOCKET_TRANSPORT_BENCHMARK_RECORD=true`
- Default output: `benchmark/socket_transport.jsonl`

Includes p95 and sample arrays for stage timings:

- encode
- decode
- send/frame serialization hop

### 3) Socket transport E2E benchmark

- Test:
  `test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart`
- Gate: `SOCKET_TRANSPORT_E2E_BENCHMARK=true`
- Optional record: `SOCKET_TRANSPORT_E2E_BENCHMARK_RECORD=true`
- Default output: `benchmark/socket_transport_e2e.jsonl`

Case keys:

- `socket_transport_e2e_rpc_roundtrip`
- `socket_transport_e2e_ack_retry`
- `socket_transport_e2e_streaming_backpressure`

## Profiles and comparability

For ODBC benchmark, profile compatibility is based on:

- `target_label`
- `build_mode`
- `database_hosting` (optional)
- `benchmark_profile`

`benchmark_profile` includes pool mode/size/concurrency and shared tuning
values. Use either:

- `ODBC_E2E_BENCHMARK_MATRIX` (recommended for multiple profiles), or
- `ODBC_E2E_BENCHMARK_POOL_MODE` + `POOL_SIZE` + `CONCURRENCY` for single run.

Default matrix when not configured:

- `lease p2 c4`
- `lease p4 c8`

## Regression guards

### Absolute thresholds

Per-case limits:

- ODBC: `ODBC_E2E_BENCHMARK_MAX_MS_*`
- Socket E2E: `SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_MS_*`

### Baseline regression budget

ODBC:

- `ODBC_E2E_BENCHMARK_BASELINE_FILE`
- `ODBC_E2E_BENCHMARK_MAX_REGRESSION_PERCENT`
- `ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS`
- `ODBC_E2E_BENCHMARK_BASELINE_WINDOW`

Socket E2E:

- `SOCKET_TRANSPORT_E2E_BENCHMARK_BASELINE_FILE`
- `SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_PERCENT`
- `SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_MS`
- `SOCKET_TRANSPORT_E2E_BENCHMARK_BASELINE_WINDOW`

## Useful commands

```bash
flutter test --tags benchmark
flutter test test/live/odbc_rpc_benchmark_live_e2e_test.dart
flutter test test/infrastructure/codecs/transport_pipeline_benchmark_test.dart
flutter test test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart
dart run tool/summarize_e2e_benchmark.dart
dart run tool/summarize_e2e_benchmark.dart benchmark/socket_transport_e2e.jsonl
```

## CI (manual workflow)

Workflow: `.github/workflows/e2e_benchmark_optional.yml`

- Supports `debug` / `profile` / `release` mode selection.
- ODBC job runs a profile matrix (including `native` pool mode).
- Socket transport E2E job can run independently.
