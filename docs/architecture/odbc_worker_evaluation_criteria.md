# ODBC Multiple Worker Evaluation Criteria

## Overview

This document defines the criteria and decision framework for evaluating whether to implement multiple `odbc_fast` workers. **Do not proceed with multiple workers without meeting these criteria first.**

## Current Architecture

- **Single `odbc_fast` worker**: One async service initialized via `ServiceLocator().initialize(useAsync: true)`
- **Lease-based connection pool**: `OdbcConnectionPool` with configurable `poolSize` (default: 4)
- **SQL execution queue**: Bounds concurrent SQL operations to prevent pool overload
- **Native RPC semaphore**: Limits concurrent calls to ODBC worker (`leasePoolNativeHandshakeConcurrency`)

## Why Multiple Workers Are Complex

1. **Connection ID partitioning**: Each worker has its own connection ID namespace
2. **Pool lifecycle management**: Each worker needs an isolated connection pool
3. **Metrics partitioning**: Tracking per-worker metrics adds complexity
4. **Cancellation coordination**: SQL cancellation must target the correct worker
5. **Increased resource usage**: More workers = more memory, threads, and overhead

## Decision Framework

### Step 1: Measure Current Bottleneck

Run E2E burst tests (see `docs/testing/sql_queue_concurrency_tests.md`) and collect these metrics:

**Required Metrics:**
- `maxConcurrentWorkers` achieved under load
- `averageQueueWaitTime` during burst
- `sqlQueueRejectionCount` and `sqlQueueTimeoutCount`
- `poolAcquireTimeoutCount` (should be near zero with queue)
- Database/driver response time (measured via query execution duration)
- ODBC worker CPU utilization (via OS tools)

### Step 2: Identify Bottleneck

Analyze where time is spent:

| Bottleneck | Evidence | Solution |
|------------|----------|----------|
| **Database/Driver** | Query execution > 100ms, low worker CPU | Optimize queries, add indexes, upgrade hardware |
| **Network** | High latency to database, low worker CPU | Improve network, move agent closer to database |
| **Connection Pool** | Frequent pool acquire waits, queue rejections | Increase `poolSize`, tune `leasePoolNativeHandshakeConcurrency` |
| **SQL Queue** | High rejection rate, low worker utilization | Increase `maxQueueSize`, tune `maxConcurrentWorkers` |
| **ODBC Worker (RPC)** | Worker CPU > 80%, database response < 10ms, queue draining slowly | **Consider multiple workers** |

### Step 3: Evaluate Multiple Workers (Only if ODBC Worker is bottleneck)

**Criteria to proceed:**

✅ **All of the following must be true:**

1. **Worker CPU sustained > 80%** during representative load
2. **Database response time < 10ms** average (not the bottleneck)
3. **Queue is backing up** despite available database capacity
4. **Single-worker throughput is insufficient** for production requirements
5. **Connection pool is healthy** (no frequent timeouts or invalid IDs)
6. **Burst tests pass consistently** with current architecture

❌ **Do NOT proceed if any of these are true:**

1. Database/driver is the bottleneck (slow queries)
2. Worker CPU < 60% sustained under load
3. Connection pool has instability (timeouts, invalid IDs, recycling issues)
4. Burst tests show other issues (leaks, deadlocks, cascading failures)

### Step 4: Design Multi-Worker Architecture

If criteria are met, design the architecture before implementation:

**Key Design Questions:**

1. **How many workers?** Start with 2, measure, then consider 3. More workers ≠ better performance.
2. **Pool size per worker?** Smaller pools per worker (e.g., 2 connections × 2 workers = 4 total)
3. **Request routing?** Round-robin, least-loaded, or hash-based (e.g., by agent ID)?
4. **Metrics aggregation?** Per-worker or aggregate? How to expose via `MetricsCollector`?
5. **Cancellation?** How to route `sql.cancel` to the correct worker?
6. **Failure handling?** What happens if one worker crashes or becomes unresponsive?

**Prototype Before Production:**

- Implement `OdbcWorkerPool` with 2 workers
- Run burst tests to measure improvement
- Compare metrics: throughput, latency, CPU, memory
- Verify no regressions in stability or error handling

### Step 5: Validate Improvement

After implementing multiple workers, validate the change:

**Success Criteria:**

- **Throughput increase** proportional to worker count (e.g., 2x workers ≈ 1.8x throughput)
- **No stability regressions** (same or better error rates, no new timeouts)
- **Resource usage acceptable** (memory and CPU increase is justified by throughput gain)
- **Metrics remain accurate** across all workers
- **Cancellation works correctly** for all workers

**If improvement is marginal (<20%)**, roll back and revisit bottleneck analysis.

## Configuration Guidance

### Starting Point (Current)

```dart
// Single worker, lease pool
ServiceLocator().initialize(useAsync: true);

final pool = OdbcConnectionPool(
  service,
  settings,
  metricsCollector: metrics,
);

final queue = SqlExecutionQueue(
  maxQueueSize: 50,
  maxConcurrentWorkers: settings.poolSize, // Align with pool
  metricsCollector: metrics,
);
```

### Multi-Worker (Only after validation)

```dart
// Pseudo-code: actual implementation depends on design decisions

final workerPool = OdbcWorkerPool(
  workerCount: 2,
  poolSizePerWorker: 2,
  metricsCollector: metrics,
);

final queue = SqlExecutionQueue(
  maxQueueSize: 50,
  maxConcurrentWorkers: 4, // 2 workers × 2 connections
  metricsCollector: metrics,
);

final gateway = MultiWorkerDatabaseGateway(
  workerPool: workerPool,
  routingStrategy: RoundRobinRouting(),
);
```

## Measurement Tools

### Profiling ODBC Worker

Use OS-level tools to measure worker CPU:

**Windows:**
```powershell
# Find Dart process
Get-Process -Name *dart* | Select-Object Id, CPU, WorkingSet

# Monitor specific process
Get-Counter "\Process(dart)\% Processor Time" -Continuous
```

**Linux:**
```bash
# Find process
ps aux | grep dart

# Monitor CPU (via top or htop)
top -p <pid>
```

### Database Response Time

Measure via `MetricsCollector`:

```dart
final executionStart = DateTime.now();
final result = await gateway.executeQuery(request);
final executionTime = DateTime.now().difference(executionStart);

print('Query execution: ${executionTime.inMilliseconds}ms');
```

Subtract queue wait time to isolate database/ODBC time.

## Summary

**Before Multiple Workers:**

1. Implement and validate SQL execution queue
2. Run E2E burst tests with representative load
3. Measure bottleneck: database, network, pool, queue, or worker
4. Tune configuration: `poolSize`, `maxQueueSize`, `maxConcurrentWorkers`

**Multiple Workers Only If:**

- Worker CPU > 80% sustained
- Database response < 10ms
- Single worker is proven bottleneck
- Burst tests pass consistently

**Otherwise:**

- Optimize database (indexes, queries, hardware)
- Tune queue and pool configuration
- Improve network latency
- Use `bulkInsert` for large batches

## References

- Main plan: `Plano Para Concorrência ODBC` (plan file)
- SQL queue tests: `docs/testing/sql_queue_concurrency_tests.md`
- Project specifics: `.cursor/rules/project_specifics.mdc`
- E2E setup: `docs/testing/e2e_setup.md`
