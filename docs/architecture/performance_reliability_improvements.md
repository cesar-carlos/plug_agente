# Performance and Reliability Improvements

## Status Atual

Após implementação do plano de concorrência ODBC, o sistema conta com:
- ✅ Fila SQL bounded (`SqlExecutionQueue`) com backpressure
- ✅ Pool de conexões lease-based (`OdbcConnectionPool`)
- ✅ Métricas de fila, workers, rejeições e timeouts
- ✅ Testes unitários cobrindo cenários de concorrência

## Melhorias Recomendadas

### Categoria: Alta Prioridade (Impacto Direto)

#### 1. Integração da Fila SQL no Fluxo RPC

**Status**: Planejado, não integrado  
**Impacto**: Alto  
**Complexidade**: Média

**Problema**:
A fila `SqlExecutionQueue` e o wrapper `QueuedDatabaseGateway` foram implementados, mas ainda não estão integrados ao fluxo RPC real. O dispatcher continua chamando o gateway ODBC diretamente.

**Solução**:
```dart
// In lib/core/di/dependencies.dart or equivalent
void setupDependencies() {
  // ... existing setup
  
  // 1. Create the base gateway
  final baseGateway = OdbcDatabaseGateway(...);
  
  // 2. Wrap with SQL execution queue
  final queue = SqlExecutionQueue(
    maxQueueSize: 50,              // Tune based on load
    maxConcurrentWorkers: 4,        // Match pool size
    metricsCollector: metricsCollector,
    defaultEnqueueTimeout: Duration(seconds: 5),
  );
  
  final queuedGateway = QueuedDatabaseGateway(
    delegate: baseGateway,
    queue: queue,
  );
  
  // 3. Register queued gateway as IDatabaseGateway
  getIt.registerSingleton<IDatabaseGateway>(queuedGateway);
}
```

**Benefícios**:
- Prevenção de sobrecarga do pool ODBC em bursts
- Rejeição rápida quando sistema está saturado
- Métricas de espera e throughput por requisição

**Riscos**:
- Aumenta latência de requisições quando fila está cheia
- Requer tuning de `maxQueueSize` e `maxConcurrentWorkers`

**Métrica de Sucesso**:
- Zero timeouts de pool durante bursts de 100+ requisições simultâneas
- `sql_queue_rejection_count` < 5% das requisições totais em produção

---

#### 2. Tuning de Limites de Concorrência

**Status**: Valores padrão conservadores  
**Impacto**: Alto  
**Complexidade**: Baixa

**Problema**:
Valores atuais são conservadores e podem estar sublotando o sistema:
- `defaultPoolSize: 4` (ConnectionConstants)
- `maxConcurrentRpcHandlers: 32` (ConnectionConstants)
- `maxQueueSize`, `maxConcurrentWorkers` não configurados no DI

**Solução**:
1. Criar variáveis de ambiente para tuning:
```dart
// In ConnectionConstants
static int get poolSize => 
  int.tryParse(dotenv.env['ODBC_POOL_SIZE'] ?? '') ?? 4;

static int get sqlQueueMaxSize =>
  int.tryParse(dotenv.env['SQL_QUEUE_MAX_SIZE'] ?? '') ?? 50;

static int get sqlQueueMaxWorkers =>
  int.tryParse(dotenv.env['SQL_QUEUE_MAX_WORKERS'] ?? '') ?? 4;
```

2. Recomendar valores iniciais baseados em carga:
```env
# Light load (< 10 req/s)
ODBC_POOL_SIZE=4
SQL_QUEUE_MAX_SIZE=20
SQL_QUEUE_MAX_WORKERS=4

# Medium load (10-50 req/s)
ODBC_POOL_SIZE=8
SQL_QUEUE_MAX_SIZE=50
SQL_QUEUE_MAX_WORKERS=8

# Heavy load (> 50 req/s)
ODBC_POOL_SIZE=16
SQL_QUEUE_MAX_SIZE=100
SQL_QUEUE_MAX_WORKERS=16
```

**Benefícios**:
- Permite tuning sem rebuild
- Adaptação a características do banco (SQL Server vs SQL Anywhere)
- Facilita testes de carga

**Métrica de Sucesso**:
- CPU do worker ODBC < 80% sob carga sustentada
- Latência P95 de `sql.execute` < 200ms

---

#### 3. Circuit Breaker para Conexões Falhando

**Status**: Não implementado  
**Impacto**: Alto  
**Complexidade**: Média

**Problema**:
Quando um banco fica indisponível, o sistema continua tentando conectar a cada requisição, gastando timeout completo e piorando latências.

**Solução**:
```dart
class ConnectionCircuitBreaker {
  ConnectionCircuitBreaker({
    required int failureThreshold,  // e.g., 5
    required Duration resetTimeout, // e.g., 30s
  });

  ConnectionState state = ConnectionState.closed;
  int consecutiveFailures = 0;
  DateTime? openedAt;

  Future<Result<T>> execute<T>(
    String connectionString,
    Future<Result<T>> Function() operation,
  ) async {
    if (state == ConnectionState.open) {
      final elapsed = DateTime.now().difference(openedAt!);
      if (elapsed < resetTimeout) {
        return Failure(ConnectionFailure(
          'Circuit breaker open for $connectionString',
        ));
      }
      // Try half-open
      state = ConnectionState.halfOpen;
    }

    final result = await operation();
    
    return result.fold(
      (success) {
        _onSuccess();
        return Success(success);
      },
      (failure) {
        if (failure is ConnectionFailure) {
          _onFailure();
        }
        return Failure(failure);
      },
    );
  }

  void _onSuccess() {
    consecutiveFailures = 0;
    if (state == ConnectionState.halfOpen) {
      state = ConnectionState.closed;
    }
  }

  void _onFailure() {
    consecutiveFailures++;
    if (consecutiveFailures >= failureThreshold) {
      state = ConnectionState.open;
      openedAt = DateTime.now();
    }
  }
}

enum ConnectionState { closed, open, halfOpen }
```

**Integração**:
```dart
class OdbcDatabaseGateway {
  final Map<String, ConnectionCircuitBreaker> _breakers = {};

  Future<Result<QueryResponse>> executeQuery(...) async {
    final breaker = _breakers.putIfAbsent(
      connectionString,
      () => ConnectionCircuitBreaker(
        failureThreshold: 5,
        resetTimeout: Duration(seconds: 30),
      ),
    );

    return breaker.execute(connectionString, () async {
      // ... existing query logic
    });
  }
}
```

**Benefícios**:
- Falha rápida quando banco está indisponível
- Reduz carga no banco durante recovery
- Melhora UX com erros imediatos vs timeouts longos

**Métrica de Sucesso**:
- Tempo de resposta de erro < 100ms quando circuit breaker open
- Recuperação automática após banco voltar (dentro de `resetTimeout`)

---

### Categoria: Média Prioridade (Otimizações)

#### 4. Pool Warm-up no Startup

**Status**: Conexões criadas sob demanda  
**Impacto**: Médio  
**Complexidade**: Baixa

**Problema**:
Primeiras requisições após startup pagam custo de handshake ODBC completo (pode ser 200-500ms).

**Solução**:
```dart
class OdbcConnectionPool {
  Future<void> warmUp(String connectionString) async {
    final connectionIds = <String>[];
    
    try {
      // Pré-aloca metade do pool
      final warmUpCount = (_settings.poolSize / 2).ceil();
      
      for (var i = 0; i < warmUpCount; i++) {
        final result = await acquire(connectionString);
        result.fold(
          (id) => connectionIds.add(id),
          (error) {
            developer.log(
              'Warm-up connection failed',
              name: 'connection_pool',
              level: 900,
              error: error,
            );
          },
        );
      }
      
      developer.log(
        'Pool warmed up with $warmUpCount connections',
        name: 'connection_pool',
      );
    } finally {
      // Libera todas as conexões pré-alocadas
      for (final id in connectionIds) {
        await release(id);
      }
    }
  }
}
```

**Benefícios**:
- Latência P99 reduzida em 30-50% nas primeiras requisições
- Detecção precoce de problemas de conexão

**Métrica de Sucesso**:
- Primeira requisição após startup < 150ms (vs ~400ms atual)

---

#### 5. Adaptive Buffer Sizing

**Status**: Implementado mas não otimizado  
**Impacto**: Médio  
**Complexidade**: Baixa

**Problema**:
`OdbcAdaptiveBufferCache` existe mas valores iniciais podem ser melhorados baseado em análise de queries reais.

**Solução**:
1. Adicionar métricas de hit/miss do buffer cache:
```dart
class OdbcAdaptiveBufferCache {
  int _cacheHits = 0;
  int _cacheMisses = 0;
  
  BufferSizeRecommendation recommend(...) {
    final result = // ... existing logic
    
    if (result.expandBuffer) {
      _cacheMisses++;
    } else {
      _cacheHits++;
    }
    
    metricsCollector?.recordBufferCacheStats(
      hits: _cacheHits,
      misses: _cacheMisses,
      hitRate: _cacheHits / (_cacheHits + _cacheMisses),
    );
    
    return result;
  }
}
```

2. Exportar métricas para análise:
- Buffer expansions por query signature
- Hit rate do cache adaptativo
- Tamanho médio de resultado por tipo de query

**Benefícios**:
- Menos realocações de buffer em queries recorrentes
- Dados para otimizar `defaultInitialResultBufferBytes`

**Métrica de Sucesso**:
- Buffer cache hit rate > 80%
- < 5% de queries requerem expansão de buffer

---

#### 6. Query Result Streaming para Grandes Datasets

**Status**: Streaming implementado mas limitado a Playground  
**Impacto**: Médio  
**Complexidade**: Alta

**Problema**:
Queries que retornam 100k+ linhas carregam todo resultado em memória antes de retornar ao hub.

**Solução Atual**:
`StreamingDatabaseGateway` existe mas só é usado em Playground.

**Recomendação**:
1. Adicionar flag no protocolo para habilitar streaming:
```json
{
  "method": "sql.execute",
  "params": {
    "statement": "SELECT * FROM large_table",
    "streaming": true,
    "chunkSize": 1000
  }
}
```

2. No dispatcher, rotear para streaming quando flag estiver presente:
```dart
Future<RpcResponse> handleSqlExecute(...) async {
  if (params['streaming'] == true) {
    return _handleStreamingQuery(request, params);
  }
  // ... existing buffered logic
}
```

**Benefícios**:
- Reduz pico de memória em queries grandes
- Permite cancelamento mid-stream
- First byte latency melhor

**Trade-offs**:
- Protocolo mais complexo (pull-based chunks)
- Requer mudanças no hub

**Métrica de Sucesso**:
- Queries > 50k linhas usam < 100MB de RAM
- Time-to-first-chunk < 500ms

---

### Categoria: Baixa Prioridade (Nice-to-have)

#### 7. Query Plan Caching

**Status**: Não implementado  
**Impacto**: Baixo-Médio  
**Complexidade**: Alta

**Problema**:
Queries parametrizadas idênticas refazem prepare/parse no banco a cada execução.

**Solução**:
```dart
class PreparedStatementCache {
  final Map<String, PreparedStatement> _cache = {};
  final int maxSize;

  Future<Result<PreparedStatement>> getOrPrepare(
    String sql,
    Connection connection,
  ) async {
    final cached = _cache[sql];
    if (cached != null && cached.isValid) {
      return Success(cached);
    }

    final result = await connection.prepare(sql);
    return result.fold(
      (stmt) {
        if (_cache.length >= maxSize) {
          _evictOldest();
        }
        _cache[sql] = stmt;
        return Success(stmt);
      },
      (error) => Failure(error),
    );
  }

  void _evictOldest() {
    final oldest = _cache.keys.first;
    _cache[oldest]?.dispose();
    _cache.remove(oldest);
  }
}
```

**Benefícios**:
- ~10-20% redução de latência em queries parametrizadas
- Menos carga de parse no banco

**Riscos**:
- Complexidade de lifecycle (quando invalidar?)
- Prepared statements podem ficar stale após schema changes

**Métrica de Sucesso**:
- Cache hit rate > 60% em workloads típicos
- Latência de queries parametrizadas -15%

---

#### 8. Retry com Exponential Backoff

**Status**: Retry existe mas é linear  
**Impacto**: Baixo  
**Complexidade**: Baixa

**Problema**:
`IRetryManager` atual usa backoff fixo, o que pode agravar cascata de falhas.

**Solução**:
```dart
class ExponentialBackoffRetryManager implements IRetryManager {
  @override
  Future<Result<T>> execute<T>(...) async {
    var attempt = 0;
    var delay = initialDelay;

    while (attempt < maxAttempts) {
      attempt++;
      
      final result = await operation();
      if (result.isSuccess() || !shouldRetry(result.exceptionOrNull())) {
        return result;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).toInt(),
        );
        delay = delay > maxDelay ? maxDelay : delay;
      }
    }
    
    return Failure(...);
  }
}
```

**Benefícios**:
- Melhor comportamento sob carga
- Reduz "thundering herd" problem

---

## Próximos Passos Recomendados

### Fase 1: Ativação Imediata (1-2 dias)
1. ✅ **Integrar `QueuedDatabaseGateway` no DI**
   - Prioridade: CRÍTICA
   - Impacto: Alto
   - Risco: Baixo (já testado)

2. ✅ **Adicionar variáveis de ambiente para tuning**
   - Prioridade: ALTA
   - Impacto: Alto
   - Risco: Baixo

3. ✅ **Pool warm-up no startup**
   - Prioridade: ALTA
   - Impacto: Médio
   - Risco: Baixo

### Fase 2: Testes de Carga (3-5 dias)
1. **Executar testes E2E de burst** (já documentados em `sql_queue_concurrency_tests.md`)
2. **Coletar métricas de baseline**:
   - Latências P50, P95, P99
   - Queue rejection rate
   - Buffer cache hit rate
   - Pool saturation events

3. **Tunar limites** baseado em resultados

### Fase 3: Hardening (1-2 semanas)
1. **Implementar circuit breaker**
2. **Otimizar adaptive buffer cache**
3. **Adicionar query streaming para RPC** (se necessário)

### Fase 4: Observabilidade (contínua)
1. **Exportar métricas para Prometheus/Grafana**
2. **Criar dashboards de performance**:
   - SQL Queue metrics (size, rejections, wait times)
   - ODBC Pool metrics (active, idle, timeouts)
   - Query latencies por tipo
   - Error rates por categoria

3. **Alertas**:
   - Queue rejection rate > 10%
   - Pool acquisition timeout > 5/min
   - Circuit breaker open > 60s

---

## Métricas de Sucesso Global

### Performance
- **Latência P95**: < 200ms para queries simples
- **Throughput**: > 100 req/s sustentado sem degradação
- **Pool saturation**: < 1% de timeouts em carga normal

### Confiabilidade
- **Uptime**: 99.9% (excluindo manutenção planejada)
- **Recovery time**: < 30s após falha de banco
- **Error rate**: < 0.1% em condições normais

### Eficiência de Recursos
- **Memória**: < 500MB sob carga pesada
- **CPU**: < 70% média, < 90% picos
- **Conexões**: Reuso > 95% (baixo churn de pool)

---

## Referências

- Plano de Concorrência ODBC: `docs/architecture/odbc_concurrency_plan_e499a5bb.plan.md`
- Testes de Concorrência: `docs/testing/sql_queue_concurrency_tests.md`
- Critérios de Workers: `docs/architecture/odbc_worker_evaluation_criteria.md`
- Documentação `odbc_fast`: https://github.com/cesar-carlos/dart_odbc_fast
