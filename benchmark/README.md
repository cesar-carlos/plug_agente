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

### 4) GZIP byte primitives (VM zlib)

- Test: `test/benchmark/gzip_codec_benchmark_test.dart`
- Gate: `CODEC_GZIP_BENCHMARK=true` (**process environment**, not read from `.env` by the test)
- Optional: `CODEC_GZIP_BENCHMARK_ITERATIONS` (default 24), `CODEC_GZIP_BENCHMARK_PAYLOAD_KB` (default 256)
- Measures: `gzipCompressBytesOrThrow` / `gzipDecompressBytesOrThrow` (`dart:io` gzip), used by `TransportPipeline` and `GzipCompressor`

### 5) GzipCompressor (rows + base64 wrapper)

- Test: `test/benchmark/gzip_compressor_benchmark_test.dart`
- Gate: `GZIP_COMPRESSOR_BENCHMARK=true` (**process environment**)
- Optional: `GZIP_COMPRESSOR_BENCHMARK_ITERATIONS`, `GZIP_COMPRESSOR_BENCHMARK_SMALL_ROWS`, `GZIP_COMPRESSOR_BENCHMARK_LARGE_ROWS`, `GZIP_COMPRESSOR_BENCHMARK_LARGE_ROW_PAYLOAD_CHARS`
- Covers sync path (small UTF-8 JSON) vs `compute` path (large JSON), aligned with `gzipRowComputeMinUtf8Bytes` in `lib/infrastructure/compression/gzip_compressor.dart`

### 6) Micro-benchmarks (validation, mapping, serialization)

Gated via `.env` / `Platform.environment` (same merge as `E2EEnv`), tag `benchmark`, optional JSONL append with `*_RECORD=true`.

| Suite | Test file | Gate | Notes |
| --- | --- | --- | --- |
| RPC request schema | `test/infrastructure/validation/rpc_request_schema_benchmark_test.dart` | `RPC_REQUEST_SCHEMA_BENCHMARK=true` | `*_BATCH_SIZE`, `*_ITERATIONS`, `*_FILE` |
| RPC contract | `test/infrastructure/validation/rpc_contract_benchmark_test.dart` | `RPC_CONTRACT_BENCHMARK=true` | `*_RESULT_ROWS`, `*_ITERATIONS` |
| ODBC row map | `test/infrastructure/external_services/odbc_result_map_benchmark_test.dart` | `ODBC_RESULT_MAP_BENCHMARK=true` | `*_ROWS`, `*_COLS`, offline |
| Query normalizer | `test/application/services/query_normalizer_benchmark_test.dart` | `QUERY_NORMALIZER_BENCHMARK=true` | `*_ROWS` |
| Canonical JSON (idempotency) | `test/application/rpc/canonicalize_json_benchmark_test.dart` | `CANONICALIZE_JSON_BENCHMARK=true` | `*_MAP_KEYS` |
| Payload codec | `test/infrastructure/codecs/payload_codec_benchmark_test.dart` | `PAYLOAD_CODEC_BENCHMARK=true` | `*_LIST_LEN` |
| Stream chunk JSON | `test/infrastructure/streaming/stream_chunk_serialize_benchmark_test.dart` | `STREAM_CHUNK_SERIALIZE_BENCHMARK=true` | `*_ROWS` |
| Idempotency store | `test/infrastructure/stores/idempotency_store_benchmark_test.dart` | `IDEMPOTENCY_STORE_BENCHMARK=true` | `*_ENTRIES` |
| SQL execute result map | `test/application/rpc/sql_execute_result_payload_benchmark_test.dart` | `SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK=true` | `*_RESULT_SETS`, `*_ROWS` |
| SQL scan (split + dangerous) | `test/core/utils/sql_scan_benchmark_test.dart` | `SQL_SCAN_BENCHMARK=true` | `*_LITERAL_CLAUSES` |
| SqlValidator | `test/application/validation/sql_validator_benchmark_test.dart` | `SQL_VALIDATOR_BENCHMARK=true` | `*_SPACE_PAD`, `*_ORDER_TERMS` (2 test cases) |
| SqlOperationClassifier | `test/application/services/sql_classifier_benchmark_test.dart` | `SQL_CLASSIFIER_BENCHMARK=true` | `*_SPACE_PAD` |
| JSON size heuristic | `test/core/utils/json_size_heuristic_benchmark_test.dart` | `JSON_SIZE_HEURISTIC_BENCHMARK=true` | `*_MAP_KEYS`, `*_BUDGET` |
| Client token hash | `test/core/utils/client_token_hash_benchmark_test.dart` | `CLIENT_TOKEN_HASH_BENCHMARK=true` | `*_TOKEN_CHARS` |
| RpcBatch parse | `test/domain/protocol/rpc_batch_parse_benchmark_test.dart` | `RPC_BATCH_PARSE_BENCHMARK=true` | `*_PARAM_PAD` (size 32 batch) |
| RpcRequestGuard | `test/infrastructure/external_services/rpc_request_guard_benchmark_test.dart` | `RPC_REQUEST_GUARD_BENCHMARK=true` | `*_EVALUATIONS`, `*_REPLAY_CAP` |
| Failure → RpcError map | `test/application/mappers/failure_to_rpc_error_mapper_benchmark_test.dart` | `FAILURE_TO_RPC_ERROR_MAPPER_BENCHMARK=true` | `*_ROUNDS` |
| Policy JWT decode-only | `test/infrastructure/services/authorization_policy_decode_benchmark_test.dart` | `POLICY_DECODE_BENCHMARK=true` | `*_PAYLOAD_PAD`, async |

Also: **Idempotency fingerprint** (`IDEMPOTENCY_FINGERPRINT_BENCHMARK`) and **RetryManager** (`RETRY_MANAGER_BENCHMARK`) in `test/application/` and `test/infrastructure/retry/`.

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
CODEC_GZIP_BENCHMARK=true flutter test test/benchmark/gzip_codec_benchmark_test.dart --tags benchmark
GZIP_COMPRESSOR_BENCHMARK=true flutter test test/benchmark/gzip_compressor_benchmark_test.dart --tags benchmark
dart run tool/summarize_e2e_benchmark.dart
dart run tool/summarize_e2e_benchmark.dart benchmark/socket_transport_e2e.jsonl
```

## CI (manual workflow)

Workflow: `.github/workflows/e2e_benchmark_optional.yml`

- Supports `debug` / `profile` / `release` mode selection.
- ODBC job runs a profile matrix (including `native` pool mode).
- Socket transport E2E job can run independently.
