# Quick Start: Melhorias de Performance e Confiabilidade

## 🚀 Ativação Imediata

As melhorias estão **ativas por padrão** após merge/pull. Não é necessário configuração adicional para funcionamento básico.

## ⚙️ Tuning Opcional

### 1. Criar arquivo `.env` (se não existir)
```bash
cp .env.example .env
```

### 2. Configurar para sua carga
Editar `.env` e descomentar/ajustar:

```env
# Para carga média (10-50 req/s) - RECOMENDADO PARA MAIORIA
ODBC_POOL_SIZE=8
SQL_QUEUE_MAX_SIZE=50
SQL_QUEUE_MAX_WORKERS=8
SQL_QUEUE_TIMEOUT_SEC=5

# Circuit breaker (padrão OK para maioria)
CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
CIRCUIT_BREAKER_RESET_SEC=30
```

### 3. Reiniciar aplicação
```bash
flutter run
# ou rebuild do executável
```

## 📊 Verificar que Está Funcionando

### Logs de Startup
Procure por:
```
[plug_dependency_registrar] SQL queue initialized: maxSize=50, maxWorkers=8
[connection_pool] Warming up connection pool with 4 connections
[connection_pool] Pool warm-up completed: 4/4 connections
```

### Durante Operação
Logs de requisições SQL:
```
[sql_execution_queue] SQL request submitted (queue_size=2, active_workers=3)
[sql_execution_queue] SQL request completed (wait_time_ms=45, result=success)
```

Circuit breaker (apenas se houver falhas):
```
[circuit_breaker] Connection failure recorded (3/5)
[circuit_breaker] Circuit breaker OPENED after 5 failures
```

## 🔍 Monitoramento

### Via HealthService
O serviço está registrado no DI e pode ser acessado:

```dart
final healthService = getIt<HealthService>();
final status = healthService.getHealthStatus();
print(status);
```

Output esperado:
```json
{
  "status": "healthy",
  "timestamp": "2026-04-28T19:45:00.000Z",
  "pool": {"size": 8},
  "sql_queue": {
    "enabled": true,
    "current_size": 2,
    "max_size": 50,
    "active_workers": 3,
    "max_workers": 8,
    "rejections_total": 0,
    "timeouts_total": 0,
    "avg_wait_time_ms": 45
  },
  "queries": {
    "total": 1523,
    "errors": 12,
    "success_rate": 99.2,
    "avg_latency_ms": 156,
    "p95_latency_ms": 298,
    "p99_latency_ms": 456
  }
}
```

## ⚠️ Sinais de Alerta

### 1. Queue Rejections Alto
**Sintoma**:
```
[sql_execution_queue] SQL request REJECTED (queue full)
rejections_total > 5% do total
```

**Solução**:
```env
# Aumentar capacidade
SQL_QUEUE_MAX_SIZE=100
SQL_QUEUE_MAX_WORKERS=16
ODBC_POOL_SIZE=16
```

### 2. Circuit Breaker Abrindo Frequentemente
**Sintoma**:
```
[circuit_breaker] Circuit breaker OPENED after 5 failures
```

**Possíveis causas**:
- Banco de dados indisponível
- Connection string incorreta
- Timeout muito curto
- Rede instável

**Ações**:
1. Verificar conectividade com banco
2. Testar connection string manualmente
3. Verificar logs do banco de dados
4. Aumentar threshold se network for instável:
```env
CIRCUIT_BREAKER_FAILURE_THRESHOLD=10
```

### 3. Latência Alta (P95 > 500ms)
**Sintoma**:
```json
"p95_latency_ms": 650
```

**Investigar**:
1. Queries lentas no banco (verificar slow query log)
2. Falta de índices
3. Contenção no banco
4. Pool pequeno demais (mas queue OK):
```env
ODBC_POOL_SIZE=16
```

### 4. Queue Sempre Cheia
**Sintoma**:
```json
"current_size": 50,  // sempre igual a max_size
"active_workers": 8   // sempre igual a max_workers
```

**Significa**: Demanda > capacidade do sistema

**Soluções**:
1. **Imediato**: Aumentar workers e pool
```env
ODBC_POOL_SIZE=16
SQL_QUEUE_MAX_WORKERS=16
```

2. **Médio prazo**: Otimizar queries lentas
3. **Longo prazo**: Escalar banco horizontalmente

## 🧪 Testes de Carga

### Quick Smoke Test
```dart
// Enviar 10 queries simultâneas
for (var i = 0; i < 10; i++) {
  unawaited(gateway.executeQuery(simpleQuery));
}
```

**Esperado**:
- Todas completam com sucesso
- 0 rejections
- Latência < 200ms

### Burst Test (50 queries)
```dart
for (var i = 0; i < 50; i++) {
  unawaited(gateway.executeQuery(simpleQuery));
}
```

**Esperado**:
- Queue rejection rate < 10%
- Workers retornam a 0 após burst
- Sistema se recupera em < 5s

### Teste E2E Completo
Ver `docs/testing/sql_queue_concurrency_tests.md` para testes detalhados.

## 🐛 Troubleshooting

### Problema: "Circuit breaker open" mas banco está UP
**Causa**: Circuit breaker ainda em timeout de reset

**Solução**: Aguardar 30s (ou o valor de `CIRCUIT_BREAKER_RESET_SEC`)

**Solução Imediata** (apenas desenvolvimento):
```dart
// Resetar manualmente (não fazer em produção!)
final gateway = getIt<IDatabaseGateway>();
if (gateway is OdbcDatabaseGateway) {
  gateway._circuitBreakers[connectionString]?.reset();
}
```

### Problema: Pool warm-up falhando
**Sintoma**:
```
[connection_pool] Warm-up connection 1/4 failed
```

**Causa Comum**: Connection string incorreta ou banco indisponível

**Ação**: 
1. App continua funcionando (warm-up é opcional)
2. Verificar connection string
3. Testar conexão manual

### Problema: "SQL execution queue disposed before request..."
**Causa**: Request enviado durante shutdown

**Normal**: Esperado durante encerramento do app
**Anormal**: Se ocorrer durante operação normal → bug no lifecycle

## 📞 Suporte

### Logs Importantes para Debug
1. Startup:
   - `[plug_dependency_registrar]` - Inicialização da queue
   - `[connection_pool]` - Warm-up

2. Operação:
   - `[sql_execution_queue]` - Fluxo de requisições
   - `[circuit_breaker]` - Estado das conexões

3. Shutdown:
   - `[service_locator]` - Sequência de disposição

### Métricas para Reportar
Ao reportar problemas, incluir:
```dart
final health = getIt<HealthService>().getHealthStatus();
print(JsonEncoder.withIndent('  ').convert(health));
```

### Issues Conhecidos
Nenhum no momento. Ver [GitHub Issues](https://github.com/cesar-carlos/plug_agente/issues) para lista atualizada.

---

## ✅ Checklist Pós-Deploy

Após deploy em produção:

- [ ] Verificar logs de startup (queue initialized, pool warmed up)
- [ ] Monitorar rejections por 1h (deve ser < 1%)
- [ ] Verificar latências P95/P99
- [ ] Confirmar que circuit breaker não está abrindo desnecessariamente
- [ ] Ajustar limites se necessário baseado em carga real
- [ ] Documentar configuração final em runbook

---

**Dúvidas?** Ver `docs/architecture/performance_reliability_improvements.md` para detalhes técnicos completos.
