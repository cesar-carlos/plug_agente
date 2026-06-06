import 'dart:io';
import 'dart:math' as math;

import 'package:plug_agente/infrastructure/config/odbc_result_encoding_parser.dart';

const int _defaultPoolSize = 8;
const int _defaultSqlQueueMaxSize = 16;
const int _defaultSqlQueueTimeoutSeconds = 5;
const int _defaultPoolAcquireTimeoutSeconds = 30;
const String _defaultAppVersion = '1.6.7';

Map<String, String> readProcessEnvironmentWithDotEnv({
  String envFileName = '.env',
  String? startDirectory,
}) {
  final merged = <String, String>{
    ...Platform.environment,
  };

  final dotEnvFile = resolveDotEnvFile(
    envFileName: envFileName,
    startDirectory: startDirectory,
  );
  if (dotEnvFile == null || !dotEnvFile.existsSync()) {
    return merged;
  }

  for (final line in dotEnvFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    final separatorIndex = trimmed.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    final key = trimmed.substring(0, separatorIndex).trim();
    final value = trimmed.substring(separatorIndex + 1).trim();
    if (key.isEmpty) {
      continue;
    }

    merged[key] = value;
  }

  return merged;
}

File? resolveDotEnvFile({
  String envFileName = '.env',
  String? startDirectory,
}) {
  var current = Directory(startDirectory ?? Directory.current.path);
  for (var i = 0; i < 12; i++) {
    final candidate = File('${current.path}${Platform.pathSeparator}$envFileName');
    if (candidate.existsSync()) {
      return candidate;
    }

    final pubspec = File('${current.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspec.existsSync()) {
      break;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  return null;
}

Future<Map<String, Object?>> buildOdbcHealthSnapshotTemplate({
  required Map<String, String> environment,
  int? processorCount,
  String? startDirectory,
}) async {
  final poolSize = _positiveIntEnv(environment, 'ODBC_POOL_SIZE') ?? _defaultPoolSize;
  final queueMaxSize = _intEnv(environment, 'SQL_QUEUE_MAX_SIZE') ?? _defaultSqlQueueMaxSize;
  final queueMaxWorkers = _positiveIntEnv(environment, 'SQL_QUEUE_MAX_WORKERS') ?? poolSize;
  final queueTimeoutSeconds = _intEnv(environment, 'SQL_QUEUE_TIMEOUT_SEC') ?? _defaultSqlQueueTimeoutSeconds;
  final effectiveProcessorCount = processorCount ?? Platform.numberOfProcessors;
  final asyncWorkerCount = _resolveAsyncWorkerCount(
    environment: environment,
    poolSize: poolSize,
    processorCount: effectiveProcessorCount,
  );
  final asyncMaxPendingRequests = _positiveIntEnv(environment, 'ODBC_ASYNC_MAX_PENDING_REQUESTS') ?? poolSize * 4;
  final resultEncoding = resolveOdbcResultEncodingValue(
    environment[odbcResultEncodingEnvKey],
  );

  return <String, Object?>{
    'status': 'healthy',
    'timestamp': DateTime.now().toIso8601String(),
    'version': resolvePubspecVersion(startDirectory: startDirectory) ?? _defaultAppVersion,
    'odbc_runtime_tuning': <String, Object>{
      'pool_size': poolSize,
      'processor_count': effectiveProcessorCount,
      'async_worker_count': asyncWorkerCount,
      'async_max_pending_requests': asyncMaxPendingRequests,
      'async_backpressure_mode': 'failFast',
      'result_encoding': resultEncodingConfigName(resultEncoding),
    },
    'pool': <String, Object?>{
      'size': poolSize,
      'active_count': null,
      'acquire_timeout_seconds': _defaultPoolAcquireTimeoutSeconds,
      'native_pool_exposed': false,
      'strategy': 'lease',
      'effective_strategy': 'lease',
      'driver_type': null,
      'experimental_enabled': false,
      'native_eligible': null,
      'native_circuit_open': false,
      'native_circuit_failures': 0,
      'native_circuit_disabled_until': null,
      'native_options_skip_total': 0,
      'native_execution_fallback_total': 0,
      'native_compatible_acquire_attempt_total': 0,
      'native_compatible_acquire_success_total': 0,
      'native_skip_reason': null,
      'fallbacks_total': 0,
      'direct_fallbacks_total': 0,
      'native_fallbacks_total': 0,
    },
    'streaming': <String, Object>{
      'active_streams': 0,
      'cancel_requested_total': 0,
      'cancel_backpressure_total': 0,
      'disconnect_failure_total': 0,
      'disconnect_timeout_total': 0,
      'db_streaming_response_total': 0,
      'auto_db_streaming_response_total': 0,
      'prefer_db_streaming_response_total': 0,
      'allowlist_db_streaming_response_total': 0,
      'materialized_response_total': 0,
      'skip_reasons': const <String, int>{},
    },
    'direct_connections': <String, Object>{
      'active_count': 0,
      'max_active_count': 0,
      'acquire_timeout_total': 0,
      'avg_wait_time_ms': 0.0,
      'p95_wait_time_ms': 0,
      'p99_wait_time_ms': 0,
      'sample_count': 0,
      'capacity_strategy': 'half_pool_reserved',
      'max_concurrent': poolSize < 2 ? 1 : poolSize ~/ 2,
      'override_exceeds_pool': false,
    },
    'sql_queue': <String, Object>{
      'enabled': true,
      'current_size': 0,
      'max_size': queueMaxSize > 0 ? queueMaxSize : _defaultSqlQueueMaxSize,
      'active_workers': 0,
      'max_workers': queueMaxWorkers,
      'active_batch_workers': 0,
      'max_batch_workers': math.max(1, queueMaxWorkers ~/ 2),
      'active_long_query_workers': 0,
      'max_long_query_workers': math.max(1, queueMaxWorkers ~/ 2),
      'active_non_query_workers': 0,
      'max_non_query_workers': math.max(1, queueMaxWorkers ~/ 2),
      'enqueue_timeout_seconds': queueTimeoutSeconds > 0 ? queueTimeoutSeconds : _defaultSqlQueueTimeoutSeconds,
      'rejections_total': 0,
      'timeouts_total': 0,
      'avg_wait_time_ms': 0,
      'p95_wait_time_ms': 0,
      'max_recent_wait_time_ms': 0,
      'pool_wait_avg_time_ms': 0,
      'pool_wait_p95_time_ms': 0,
      'connect_avg_time_ms': 0,
      'sql_execution_avg_time_ms': 0,
      'saturation_70_total': 0,
      'saturation_90_total': 0,
      'workers_equal_pool_total': 0,
      'pool_wait_timeouts_total': 0,
    },
    'prepared': <String, Object>{
      'reuse_total': 0,
      'cache_hit_total': 0,
      'cache_miss_total': 0,
      'prepare_avg_ms': 0.0,
      'prepare_p95_ms': 0,
    },
    'timeouts': <String, Object>{
      'sql_total': 0,
      'pool_total': 0,
      'cancel_success_total': 0,
      'cancel_failure_total': 0,
    },
    'queries': <String, Object>{
      'total': 0,
      'errors': 0,
      'success_rate': 100.0,
      'avg_latency_ms': 0,
      'p95_latency_ms': 0,
      'p99_latency_ms': 0,
    },
    'sql_execution_by_mode': const <String, Object>{},
    'batch': <String, Object>{
      'read_only_parallel_total': 0,
      'read_only_parallel_capped_total': 0,
      'transactional_direct_total': 0,
      'transactional_native_pool_total': 0,
      'transactional_native_pool_fallback_total': 0,
      'bulk_insert_recommended_total': 0,
      'last_requested_parallelism': 0,
      'last_effective_parallelism': 0,
      'parallel_global_wait_avg_ms': 0.0,
      'parallel_global_wait_p95_ms': 0,
      'parallel_global_wait_p99_ms': 0,
      'parallel_global_wait_sample_count': 0,
    },
    'diagnostics': <String, Object>{
      'top_recent_reasons': const <String, int>{},
      'recent_reasons': const <String>[],
    },
    'uptime_seconds': 0,
  };
}

String? resolvePubspecVersion({String? startDirectory}) {
  var current = Directory(startDirectory ?? Directory.current.path);
  for (var i = 0; i < 12; i++) {
    final pubspec = File('${current.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspec.existsSync()) {
      for (final line in pubspec.readAsLinesSync()) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('version:')) {
          continue;
        }
        final raw = trimmed.substring('version:'.length).trim();
        if (raw.isEmpty) {
          return null;
        }
        return raw.split('+').first.trim();
      }
      return null;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  return null;
}

int? _positiveIntEnv(Map<String, String> environment, String key) {
  final parsed = int.tryParse(environment[key]?.trim() ?? '');
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

int? _intEnv(Map<String, String> environment, String key) {
  return int.tryParse(environment[key]?.trim() ?? '');
}

int _resolveAsyncWorkerCount({
  required Map<String, String> environment,
  required int poolSize,
  required int processorCount,
}) {
  final effectivePoolSize = poolSize > 0 ? poolSize : 1;
  final effectiveProcessorCount = processorCount > 0 ? processorCount : 1;
  final ceiling = math.max(1, math.min(effectivePoolSize, effectiveProcessorCount));
  final override = _positiveIntEnv(environment, 'ODBC_ASYNC_WORKER_COUNT');
  if (override == null) {
    return ceiling;
  }
  return math.min(override, ceiling);
}
