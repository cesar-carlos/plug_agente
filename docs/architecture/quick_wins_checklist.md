# Quick Wins: Performance & Reliability Checklist

## Implementações Rápidas (< 1 dia cada)

### ✅ 1. Ativar Fila SQL no Fluxo de Produção

**Tempo estimado**: 2-3 horas  
**Impacto**: ALTO  
**Arquivo**: `lib/core/di/dependencies.dart` (ou equivalente)

```dart
// Substituir registro direto do gateway:
// getIt.registerSingleton<IDatabaseGateway>(OdbcDatabaseGateway(...));

// Por versão com fila:
final baseGateway = OdbcDatabaseGateway(...);
final sqlQueue = SqlExecutionQueue(
  maxQueueSize: 50,
  maxConcurrentWorkers: 4,
  metricsCollector: getIt<MetricsCollector>(),
  defaultEnqueueTimeout: Duration(seconds: 5),
);
final queuedGateway = QueuedDatabaseGateway(
  delegate: baseGateway,
  queue: sqlQueue,
);
getIt.registerSingleton<IDatabaseGateway>(queuedGateway);
```

**Validação**:
```bash
# Após mudança, verificar que testes passam
flutter test test/application/queue/
flutter test test/application/rpc/rpc_method_dispatcher_test.dart
```

---

### ✅ 2. Configurar Limites via Variáveis de Ambiente

**Tempo estimado**: 1 hora  
**Impacto**: ALTO  
**Arquivo**: `lib/core/constants/connection_constants.dart`

```dart
class ConnectionConstants {
  // Adicionar getters configuráveis:
  static int get poolSize => 
    int.tryParse(dotenv.env['ODBC_POOL_SIZE'] ?? '') ?? defaultPoolSize;

  static int get sqlQueueMaxSize =>
    int.tryParse(dotenv.env['SQL_QUEUE_MAX_SIZE'] ?? '') ?? 50;

  static int get sqlQueueMaxWorkers =>
    int.tryParse(dotenv.env['SQL_QUEUE_MAX_WORKERS'] ?? '') ?? poolSize;

  static Duration get sqlQueueEnqueueTimeout =>
    Duration(
      seconds: int.tryParse(dotenv.env['SQL_QUEUE_TIMEOUT_SEC'] ?? '') ?? 5,
    );
}
```

**Arquivo**: `.env.example`
```env
# ODBC Performance Tuning
ODBC_POOL_SIZE=4
SQL_QUEUE_MAX_SIZE=50
SQL_QUEUE_MAX_WORKERS=4
SQL_QUEUE_TIMEOUT_SEC=5
```

**Validação**:
```bash
# Criar .env local com valores de teste
echo "ODBC_POOL_SIZE=8" > .env
echo "SQL_QUEUE_MAX_SIZE=100" >> .env

# Verificar que app lê os valores
flutter run --debug
# No console, validar logs de startup mostrando limites corretos
```

---

### ✅ 3. Adicionar Pool Warm-up no Startup

**Tempo estimado**: 2 horas  
**Impacto**: MÉDIO  
**Arquivo**: `lib/infrastructure/pool/odbc_connection_pool.dart`

```dart
class OdbcConnectionPool implements IConnectionPool {
  /// Pre-warms the pool with connections to reduce first-request latency.
  Future<void> warmUp(
    String connectionString, {
    int? warmUpCount,
  }) async {
    final count = warmUpCount ?? (_settings.poolSize / 2).ceil();
    final connectionIds = <String>[];
    
    developer.log(
      'Warming up connection pool with $count connections',
      name: 'connection_pool',
    );
    
    try {
      for (var i = 0; i < count; i++) {
        final result = await acquire(connectionString);
        result.fold(
          (id) => connectionIds.add(id),
          (error) {
            developer.log(
              'Warm-up connection $i failed',
              name: 'connection_pool',
              level: 900,
              error: error,
            );
          },
        );
      }
      
      developer.log(
        'Pool warm-up completed: ${connectionIds.length}/$count connections',
        name: 'connection_pool',
      );
    } finally {
      for (final id in connectionIds) {
        unawaited(release(id));
      }
    }
  }
}
```

**Integração no boot**:
```dart
// In lib/main.dart or boot sequence
Future<void> main() async {
  // ... existing setup
  
  final pool = getIt<IConnectionPool>() as OdbcConnectionPool;
  final config = getIt<IAgentConfigRepository>();
  
  config.getCurrentConfig().fold(
    (agentConfig) {
      if (agentConfig.connectionString.isNotEmpty) {
        unawaited(pool.warmUp(agentConfig.connectionString));
      }
    },
    (_) {},
  );
  
  runApp(const MyApp());
}
```

**Validação**:
- Primeira requisição após startup deve ter latência < 150ms (vs ~400ms sem warm-up)
- Logs devem mostrar "Pool warm-up completed"

---

### ✅ 4. Expor Métricas de Fila no Endpoint de Health

**Tempo estimado**: 1-2 horas  
**Impacto**: MÉDIO  
**Arquivo**: Criar `lib/presentation/api/health_endpoint.dart` (se não existe)

```dart
class HealthEndpoint {
  HealthEndpoint({
    required MetricsCollector metricsCollector,
    required IConnectionPool pool,
  }) : _metrics = metricsCollector,
       _pool = pool;

  final MetricsCollector _metrics;
  final IConnectionPool _pool;

  Map<String, Object> getHealthStatus() {
    final metrics = _metrics.getCurrentMetrics();
    
    return {
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
      'pool': {
        'active_leases': (_pool as OdbcConnectionPool?)?.activeLeaseCount ?? 0,
        'pool_size': ConnectionConstants.poolSize,
      },
      'sql_queue': {
        'current_size': metrics.sqlQueueCurrentSize,
        'max_size': ConnectionConstants.sqlQueueMaxSize,
        'active_workers': metrics.sqlQueueActiveWorkers,
        'max_workers': ConnectionConstants.sqlQueueMaxWorkers,
        'rejections_total': metrics.sqlQueueRejectionCount,
        'timeouts_total': metrics.sqlQueueTimeoutCount,
      },
      'queries': {
        'total': metrics.queryCount,
        'errors': metrics.queryErrorCount,
        'avg_latency_ms': metrics.avgQueryLatencyMs,
      },
    };
  }
}
```

**Expor via Socket.IO ou HTTP local** (se aplicável):
```dart
// Método RPC: "agent.getHealth"
Future<RpcResponse> handleGetHealth(RpcRequest request) async {
  final health = _healthEndpoint.getHealthStatus();
  return RpcResponse.success(
    id: request.id,
    result: health,
  );
}
```

**Validação**:
- Chamar endpoint e verificar JSON com métricas atualizadas
- Durante burst de carga, ver `sql_queue.current_size` crescer

---

### ✅ 5. Adicionar Logging Estruturado para Debugging

**Tempo estimado**: 1 hora  
**Impacto**: MÉDIO (facilita troubleshooting)  
**Arquivo**: `lib/application/queue/sql_execution_queue.dart`

```dart
class SqlExecutionQueue {
  Future<Result<T>> submit<T extends Object>(...) async {
    final submissionId = _uuid.v4().substring(0, 8);
    
    developer.log(
      'SQL request submitted',
      name: 'sql_execution_queue',
      level: 500,
      error: null,
      stackTrace: null,
      time: DateTime.now(),
      sequenceNumber: _sequenceNumber++,
      zone: Zone.current,
      json: {
        'submission_id': submissionId,
        'request_id': requestId,
        'queue_size_before': _queue.length,
        'active_workers': _activeWorkers,
        'is_full': isFull,
      },
    );
    
    // ... existing logic
    
    if (isFull) {
      developer.log(
        'SQL request REJECTED (queue full)',
        name: 'sql_execution_queue',
        level: 900,
        json: {
          'submission_id': submissionId,
          'request_id': requestId,
          'queue_size': _queue.length,
          'max_queue_size': _maxQueueSize,
          'active_workers': _activeWorkers,
        },
      );
      // ... return Failure
    }
    
    // ... after execution
    developer.log(
      'SQL request completed',
      name: 'sql_execution_queue',
      level: 500,
      json: {
        'submission_id': submissionId,
        'request_id': requestId,
        'wait_time_ms': waitTime.inMilliseconds,
        'result': result.isSuccess() ? 'success' : 'failure',
      },
    );
  }
}
```

**Validação**:
- Durante testes, filtrar logs por `sql_execution_queue`
- Verificar que `submission_id` permite rastrear requisição end-to-end

---

### ✅ 6. Adicionar Timeout Defensivo em Pool Acquire

**Tempo estimado**: 30 min  
**Impacto**: ALTO (previne deadlocks)  
**Arquivo**: `lib/infrastructure/pool/odbc_connection_pool.dart`

**Verificar se já implementado**:
```dart
@override
Future<Result<String>> acquire(String connectionString) async {
  try {
    await _semaphore.acquire(
      timeout: _acquireTimeout,  // ✅ JÁ IMPLEMENTADO
    );
  } on TimeoutException catch (error) {
    _metrics?.recordPoolAcquireTimeout();
    return Failure(...);
  }
  // ...
}
```

**Se não estiver**, adicionar:
```dart
await _semaphore.acquire(
  timeout: _acquireTimeout ?? ConnectionConstants.defaultPoolAcquireTimeout,
);
```

---

### ✅ 7. Verificar Disposição Correta da Fila no Shutdown

**Tempo estimado**: 1 hora  
**Impacto**: MÉDIO (previne resource leaks)  
**Arquivo**: DI container ou lifecycle manager

```dart
class AppLifecycleManager {
  Future<void> dispose() async {
    // Dispose SQL queue
    final gateway = getIt<IDatabaseGateway>();
    if (gateway is QueuedDatabaseGateway) {
      // QueuedDatabaseGateway should expose queue for disposal
      gateway.dispose();
    }
    
    // Dispose pool
    final pool = getIt<IConnectionPool>();
    await pool.dispose();
    
    developer.log('App resources disposed', name: 'lifecycle');
  }
}
```

**Adicionar em `QueuedDatabaseGateway`**:
```dart
class QueuedDatabaseGateway implements IDatabaseGateway {
  void dispose() {
    _queue.dispose();
  }
}
```

**Validação**:
- Fechar app e verificar que não há warnings de resources não dispostos
- Verificar que conexões ODBC foram fechadas corretamente

---

## Verificação de Sanidade (Smoke Tests)

Após implementar quick wins, executar:

### 1. Teste de Requisição Única
```bash
# Enviar uma query simples via RPC
# Verificar:
# - Latência < 200ms
# - Sem erros nos logs
# - Métricas incrementadas corretamente
```

### 2. Teste de Burst Pequeno (10 requisições)
```bash
# Enviar 10 queries simultâneas
# Verificar:
# - Todas completam com sucesso
# - Nenhuma rejeição de fila
# - Workers retornam a 0 após burst
```

### 3. Teste de Saturação (50+ requisições)
```bash
# Enviar 50-100 queries simultâneas
# Verificar:
# - Taxa de rejeição < 10%
# - Timeouts de pool = 0
# - Sistema se recupera após burst
```

### 4. Teste de Warm-up
```bash
# Reiniciar app
# Enviar primeira query
# Verificar:
# - Latência < 150ms (vs ~400ms sem warm-up)
# - Logs mostram pool pré-aquecido
```

---

## Alertas Recomendados

Se integrar com sistema de monitoramento externo:

### Críticos (Págeable)
- `sql_queue_rejection_rate > 20%` por 5 minutos
- `pool_acquisition_timeout_rate > 10/min` por 3 minutos
- `query_error_rate > 10%` por 5 minutos

### Warnings (Non-págeable)
- `sql_queue_size > 80% capacity` por 10 minutos
- `active_workers = max_workers` por 15 minutos (saturação)
- `avg_query_latency_p95 > 500ms` por 10 minutos

### Informativos
- `sql_queue_rejections > 0` (log para análise)
- `buffer_cache_hit_rate < 60%` (oportunidade de tuning)

---

## Tuning Baseado em Carga Real

Após coleta de métricas por 24-48h:

### Se `sql_queue_rejection_rate > 5%`:
```env
# Aumentar capacidade de fila
SQL_QUEUE_MAX_SIZE=100  # Era 50
SQL_QUEUE_MAX_WORKERS=8  # Era 4
ODBC_POOL_SIZE=8  # Era 4
```

### Se `avg_query_latency_p95 > 300ms` mas `queue_size < 20`:
```env
# Gargalo provavelmente está no banco, não na fila
# Investigar:
# - Slow queries
# - Falta de índices
# - Contenção no banco
```

### Se `buffer_cache_hit_rate < 60%`:
```dart
// In ConnectionConstants
static const int defaultInitialResultBufferBytes = 512 * 1024;  // Era 256KB
```

### Se `pool_saturation_events > 100/day`:
```env
# Pool pequeno demais para carga
ODBC_POOL_SIZE=16
SQL_QUEUE_MAX_WORKERS=16
```

---

## Próximos Passos Pós Quick Wins

1. **Implementar Circuit Breaker** (ver `performance_reliability_improvements.md`)
2. **Testes de Carga E2E** (seguir `sql_queue_concurrency_tests.md`)
3. **Otimizar Buffer Adaptativo** com dados reais
4. **Avaliar Query Streaming** para datasets grandes

---

## Checklist Final

Antes de considerar quick wins completos:

- [ ] Fila SQL integrada no DI e ativa em produção
- [ ] Variáveis de ambiente documentadas em `.env.example`
- [ ] Pool warm-up executando no startup
- [ ] Endpoint de health expondo métricas de fila
- [ ] Logging estruturado para debugging de performance
- [ ] Disposal correto de recursos no shutdown
- [ ] Smoke tests executados e passando
- [ ] Documentação atualizada com novos limites configuráveis
