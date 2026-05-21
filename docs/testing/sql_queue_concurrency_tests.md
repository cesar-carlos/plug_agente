# SQL Execution Queue Concurrency Tests

## Overview

This document describes the testing strategy for the SQL execution queue concurrency improvements, including unit tests, integration tests, and E2E burst tests.

## Unit Tests

### SqlExecutionQueue Tests

Location: `test/application/queue/sql_execution_queue_test.dart`

**Coverage:**
- FIFO ordering
- Bounded queue rejection when full
- Worker concurrency limits
- Queue timeout handling
- Exception handling
- Metrics collection
- Disposal cleanup

**Key Test Cases:**
1. **Queue rejection**: Verifies that requests are rejected with clear errors when the queue is full
2. **Worker limits**: Ensures no more than `maxConcurrentWorkers` tasks execute simultaneously  
3. **FIFO order**: Validates tasks are processed in submission order
4. **Timeout**: Confirms requests timeout appropriately when waiting too long in queue
5. **Exceptions**: Tests that thrown exceptions are caught and reported
6. **Metrics**: Verifies all queue metrics are recorded correctly

### QueuedDatabaseGateway Tests

Location: `test/application/gateway/queued_database_gateway_test.dart`

**Coverage:**
- Routes SQL operations through queue
- Bypasses queue for non-SQL operations (testConnection)
- Propagates rejections from full queue
- Exposes queue metrics for monitoring

## Integration Tests

### RpcMethodDispatcher Integration

`QueuedDatabaseGateway` is already integrated in the production DI graph via
`plug_dependency_registrar.dart`. The remaining gap is coverage that exercises
the dispatcher and queue together under burst conditions.

**Coverage target:**
- `sql.execute` and `sql.executeBatch` are queued
- `agent.getProfile` and `client_token.getPolicy` bypass queue
- Timeout budgets are preserved (queue wait + ODBC execution)
- Clear RPC errors when queue is full

## E2E Burst Tests (Opt-in)

### Prerequisites

E2E burst tests require a live ODBC connection and are opt-in via environment variables.

**Environment Variables:**
- `RUN_ODBC_BURST_TESTS=true` - Enable burst tests
- `ODBC_TEST_DSN` - Test database DSN  
- `ODBC_TEST_USER` - Optional username
- `ODBC_TEST_PASSWORD` - Optional password
- `ODBC_INTEGRATION_LONG_QUERY` (or DB-specific variant) - Slow SQL used to
  saturate the queue deterministically during burst tests

See `docs/testing/e2e_setup.md` for full configuration.

### Burst Test Scenarios

#### 1. Controlled Burst (50 requests)

**Location:** `test/integration/sql_queue_burst_test.dart` (to be created)

**Scenario:**
- Submit 50 SQL queries simultaneously
- Configure queue: `maxQueueSize=20`, `maxConcurrentWorkers=4`
- Expected: ~20 rejected, ~30 queued/executed
- Verify: All leases released, queue drains to zero, no pool deadlock

**Validation:**
- `metrics.sqlQueueRejectionCount` ~= 20
- `pool.getActiveCount()` returns to 0
- No timeout cascades
- Clear error messages for rejected requests

#### 2. Sustained Load (100 requests in batches)

**Scenario:**
- Submit 10 batches of 10 requests with 100ms delay between batches
- Configure queue: `maxQueueSize=15`, `maxConcurrentWorkers=4`
- Expected: Controlled rejection, predictable throughput
- Verify: System remains responsive, metrics accurate

#### 3. Pool Recovery After Burst

**Scenario:**
- Submit 80 requests to overflow queue
- Wait for burst to complete
- Submit 10 normal requests
- Expected: Normal operation resumes, no lingering issues
- Verify: All new requests succeed, queue metrics reset

### Running E2E Burst Tests

```bash
# Set environment variables
export RUN_ODBC_BURST_TESTS=true
export ODBC_TEST_DSN="DSN=MyTestDB"

# Run burst tests only
flutter test test/integration/sql_queue_burst_test.dart

# Run all E2E tests
flutter test test/integration/
```

### Metrics to Monitor

During burst tests, monitor these metrics via `MetricsCollector`:

- `sqlQueueRejectionCount` - Requests rejected (queue full)
- `sqlQueueTimeoutCount` - Requests timed out in queue
- `currentQueueSize` / `maxQueueSize` - Queue utilization
- `currentActiveWorkers` / `maxActiveWorkers` - Worker utilization
- `averageQueueWaitTime` - Average time spent waiting
- `directConnectionFallbackCount` - Direct connections (should be minimal)
- `poolAcquireTimeoutCount` - Pool timeouts (should be zero with queue)

### Success Criteria

**All burst tests must meet these criteria:**

1. **No pool deadlock**: `getActiveCount()` returns to 0 after burst
2. **Controlled rejection**: Queue full errors are clear and actionable
3. **No timeout cascades**: Worker/ODBC timeouts don't spread to unrelated requests
4. **Metrics accuracy**: All counters match expected behavior
5. **Recovery**: System handles normal load correctly after burst

## Test Execution Order

1. Run unit tests first: `flutter test test/application/queue/ test/application/gateway/`
2. Fix any unit test failures before E2E
3. Run E2E burst tests with opt-in: `RUN_ODBC_BURST_TESTS=true flutter test test/integration/`
4. Review metrics and logs for anomalies
5. Adjust `maxQueueSize` and `maxConcurrentWorkers` based on results

## Runtime Tuning Follow-up

The app now uses the internal async worker pool from `odbc_fast 3.7.0` by
default. Burst test analysis should use the ODBC diagnostic payload before
changing concurrency limits:

- `runtime_tuning.async_worker_count`
- `runtime_tuning.async_max_pending_requests`
- `async_worker_pool.pending_requests`
- `async_worker_pool.pending_saturation_percent`
- `async_worker_pool.near_pending_limit`
- `async_worker_pool.queue_wait_p95_micros`
- `sql_queue.current_size`
- `sql_queue.p95_wait_time_ms`

If E2E tests show the internal ODBC worker pool is saturated while the database
and driver still have headroom, tune:

- `ODBC_ASYNC_WORKER_COUNT`, capped by `min(ODBC_POOL_SIZE, CPU cores)`
- `ODBC_ASYNC_MAX_PENDING_REQUESTS`, for expected bursts that should wait
  inside the package instead of failing fast immediately
- `SQL_QUEUE_MAX_SIZE` and SQL queue worker limits, when app queue wait grows
  but ODBC workers are idle

Do not add multiple `ServiceLocator` instances or partitioned custom ODBC pools
for normal tuning. That architecture remains outside the default runtime path
and should only be reconsidered after the supported package worker pool has
been measured and exhausted.

## References

- Main plan: `Plano Para Concorrência ODBC` (plan file)
- E2E setup: `docs/testing/e2e_setup.md`
- Operational validation runbook: `docs/architecture/odbc_operational_validation_runbook.md`
- Project specifics: `.cursor/rules/project_specifics.mdc`
