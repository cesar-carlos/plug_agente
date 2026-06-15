# Relatório de benchmark — plug_agente

- Run ID: `20260615_160631`
- Capturado em: 2026-06-15T16:06:39-04:00
- Commit: `a625d39645d1f068ad6ed91278fb4de3e7c07185` (main)
- Working tree dirty: True
- Plataforma: Windows-11-10.0.26200-SP0

## Suites

### odbc_async
- Status: **pass**
- Wall time: 5316.54 ms
- Log: `odbc_async.log`
- Métricas:
  - `wall_ms`: 5316.536299942527

### odbc_streaming
- Status: **pass**
- Wall time: 1983.42 ms
- Log: `odbc_streaming.log`
- Métricas:
  - `wall_ms`: 1983.4172999835573

## Comparação com baseline

```bash
python tool/benchmarks/compare_benchmark_summary.py \
  --baseline benchmarks/baseline/summary.json \
  --current benchmarks/results/20260615_160631/summary.json
```
