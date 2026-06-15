# Relatório de benchmark — plug_agente

- Run ID: `20260615_150418`
- Capturado em: 2026-06-15T15:04:21-04:00
- Commit: `ae7c2e314fb27e497f477f9e2a23af4b4d6353da` (main)
- Working tree dirty: True
- Plataforma: Windows-11-10.0.26200-SP0

## Suites

### odbc_streaming
- Status: **pass**
- Wall time: 3258.11 ms
- Log: `odbc_streaming.log`
- Métricas:
  - `wall_ms`: 3258.1146999727935

## Comparação com baseline

```bash
python tool/benchmarks/compare_benchmark_summary.py \
  --baseline benchmarks/baseline/summary.json \
  --current benchmarks/results/20260615_150418/summary.json
```
