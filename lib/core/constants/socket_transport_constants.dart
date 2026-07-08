import 'package:plug_agente/core/constants/connection_constants_env.dart';
import 'package:plug_agente/core/constants/sql_queue_constants.dart';

/// Socket.IO transport, RPC backpressure, and pipeline tuning limits.
abstract final class SocketTransportConstants {
  SocketTransportConstants._();

  static const int socketConnectionTimeoutMs = 10000;
  static const int socketAckTimeoutMs = 8000;

  /// Timeout for hub to respond with agent:capabilities after agent:register.
  static const int capabilitiesTimeoutMs = 8000;

  /// Max agent:register retries before forcing reconnect when capabilities missing.
  static const int capabilitiesMaxReRegisterAttempts = 2;

  /// Extra slack for the presentation-layer negotiating watchdog beyond transport
  /// register + re-register cycles.
  static const int capabilitiesNegotiationWatchdogMarginMs = 2000;

  /// UI backstop when hub status stays negotiating beyond transport capability
  /// timeout cycles (initial register + [capabilitiesMaxReRegisterAttempts] retries).
  static int get capabilitiesNegotiationWatchdogMs =>
      capabilitiesTimeoutMs * (capabilitiesMaxReRegisterAttempts + 1) + capabilitiesNegotiationWatchdogMarginMs;

  static const Duration socketHeartbeatInterval = Duration(seconds: 20);
  static const Duration socketHeartbeatAckTimeout = Duration(seconds: 8);
  static const int socketMaxMissedHeartbeats = 2;

  static const int maxConnectionPools = 64;
  static const int maxBackpressureChunkQueueSize = 1000;

  /// Headroom above SQL queue soft limit for concurrent non-sql
  /// RPC handlers on the same socket (health, profile, batch, etc.).
  static const int defaultMaxConcurrentRpcHandlersHeadroom = 96;

  /// Max in-flight `rpc:request` handlers per socket connection (backpressure).
  ///
  /// Defaults to SQL queue soft limit plus [defaultMaxConcurrentRpcHandlersHeadroom].
  /// Override with env `MAX_CONCURRENT_RPC_HANDLERS`.
  static int get maxConcurrentRpcHandlers =>
      ConnectionConstantsEnv.positiveInt('MAX_CONCURRENT_RPC_HANDLERS') ??
      SqlQueueConstants.rpcSqlExecuteConcurrencySoftLimit + defaultMaxConcurrentRpcHandlersHeadroom;

  /// Max simultaneously registered RPC streaming emitters per socket connection.
  /// Each emitter holds buffered chunks awaiting `rpc:stream.pull` from the hub;
  /// the cap protects memory if streams never receive a final pull/complete.
  static const int maxConcurrentRpcStreams = 640;

  /// Idle timeout for an RPC streaming emitter. If the hub does not call
  /// `rpc:stream.pull` within this window after the last activity, the emitter
  /// is unregistered defensively to avoid leaks across long-lived sockets.
  static const Duration rpcStreamEmitterMaxIdle = Duration(seconds: 300);

  /// Max distinct receive-pipeline entries cached per socket connection.
  /// Each entry is keyed by `(encoding, compression, schemaVersion, threshold)`.
  /// LRU eviction; raise this if `pipeline_cache_eviction` metrics show churn.
  static const int receivePipelineCacheMaxEntries = 16;

  /// Default max successful `client_token.getPolicy` calls per minute per agent+credential scope.
  /// Override with env `CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE` (`0` = unlimited).
  static const int clientTokenGetPolicyDefaultMaxPerMinute = 1200;

  /// Max distinct agent+credential scopes tracked by the getPolicy rate limiter at once.
  /// Override with env `CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS` (`0` = no cap on distinct keys).
  static const int clientTokenGetPolicyDefaultMaxScopeKeys = 8192;

  /// UTF-8 JSON size above which message tracing replaces the raw payload with a
  /// summary (when `FeatureFlags.enableSocketSummarizeLargePayloadLogs` is on).
  static const int socketLogPayloadSummaryThresholdBytes = 8192;

  /// Inbound `rpc:request` payloads above this UTF-8 size skip JSON Schema
  /// validation to avoid O(payload) cost on already-size-limited messages.
  /// Requests this large already passed the negotiated payload limit check.
  static const int defaultSchemaValidationSkipAboveBytes = 128 * 1024;

  /// Effective inbound schema-validation skip threshold.
  ///
  /// Override with env `INBOUND_SCHEMA_VALIDATION_SKIP_ABOVE_BYTES` (positive
  /// integer bytes). `0` disables the soft cap (always validate).
  static int get schemaValidationSkipAboveBytes {
    final override = ConnectionConstantsEnv.positiveInt('INBOUND_SCHEMA_VALIDATION_SKIP_ABOVE_BYTES');
    if (override != null) {
      return override;
    }
    return defaultSchemaValidationSkipAboveBytes;
  }

  /// Outgoing `rpc:response` contract validation is skipped above this UTF-8 JSON
  /// size to limit CPU on huge results (0 disables the soft cap).
  static const int socketOutgoingContractValidationMaxBytes = 2 * 1024 * 1024;

  /// Default payload size above which GZIP compress/decompress runs in a background isolate.
  ///
  /// Send path compares UTF-8 size before compression; receive path compares
  /// `originalSize` from frame metadata (decoded payload size), not wire bytes.
  /// Benchmark sweep (2026-05, async path, SQL + blob cases): 32 KiB matched or
  /// beat 16 KiB on p95 receive for large gzip payloads while avoiding extra isolate
  /// churn on sub-threshold frames; 64 KiB increased main-isolate gzip cost without
  /// clear win. Tune with `TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES` or
  /// `tool/benchmarks/benchmark_transport_pipeline.dart --gzip-isolate-threshold-sweep`.
  static const int defaultGzipIsolateThresholdBytes = 32 * 1024;

  /// JSON tree size above which `rpc:chunk` / `rpc:complete` encoding uses `compute`.
  ///
  /// Lower than `jsonPayloadIsolateEncodeThresholdBytes` so streaming row payloads
  /// do not block the UI isolate between ODBC fetches.
  static const int streamingChunkJsonIsolateThresholdBytes = 32 * 1024;

  /// Row count in an `rpc:chunk` payload above which JSON encoding always uses
  /// `compute`, even when the byte-size heuristic is below
  /// [streamingChunkJsonIsolateThresholdBytes].
  static const int streamingChunkRowIsolateThreshold = 50;

  /// Dedicated `rpc:chunk` JSON encode isolate threshold (lower than generic
  /// responses so frequent small chunks stay off the UI isolate).
  static const int defaultRpcChunkJsonIsolateThresholdBytes = 16 * 1024;

  static int get rpcChunkJsonIsolateThresholdBytes =>
      ConnectionConstantsEnv.positiveInt('RPC_CHUNK_JSON_ISOLATE_THRESHOLD_BYTES') ??
      defaultRpcChunkJsonIsolateThresholdBytes;

  /// Dedicated `rpc:chunk` gzip isolate threshold.
  static const int defaultRpcChunkGzipIsolateThresholdBytes = 16 * 1024;

  static int get rpcChunkGzipIsolateThresholdBytes =>
      ConnectionConstantsEnv.positiveInt('RPC_CHUNK_GZIP_ISOLATE_THRESHOLD_BYTES') ??
      defaultRpcChunkGzipIsolateThresholdBytes;

  /// GZIP compression threshold for `rpc:chunk` / `rpc:complete` only.
  static const int defaultRpcChunkCompressionThresholdBytes = 2048;

  static int get rpcChunkCompressionThresholdBytes =>
      ConnectionConstantsEnv.positiveInt('RPC_CHUNK_COMPRESSION_THRESHOLD_BYTES') ??
      defaultRpcChunkCompressionThresholdBytes;

  /// Row-count isolate threshold dedicated to `rpc:chunk` events.
  static const int defaultRpcChunkRowIsolateThreshold = 32;

  static int get rpcChunkRowIsolateThreshold =>
      ConnectionConstantsEnv.positiveInt('RPC_CHUNK_ROW_ISOLATE_THRESHOLD') ?? defaultRpcChunkRowIsolateThreshold;

  /// When false (default), columnar `rpc:chunk` payloads skip gzip because they
  /// are typically low compressibility. Override with
  /// `RPC_CHUNK_COLUMNAR_GZIP_ENABLED` (`true`/`false`).
  static const bool defaultRpcChunkColumnarGzipEnabled = false;

  static bool get rpcChunkColumnarGzipEnabled {
    final raw = ConnectionConstantsEnv.optional('RPC_CHUNK_COLUMNAR_GZIP_ENABLED');
    if (raw == null || raw.isEmpty) {
      return defaultRpcChunkColumnarGzipEnabled;
    }
    final normalized = raw.toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultRpcChunkColumnarGzipEnabled;
  }

  /// Sample rate for `rpc:chunk` protocol metrics (record 1 in N events).
  /// Override with `PROTOCOL_METRICS_RPC_CHUNK_SAMPLE_RATE` (integer >= 1).
  static const int defaultProtocolMetricsRpcChunkSampleRate = 10;

  static int get protocolMetricsRpcChunkSampleRate {
    final parsed = ConnectionConstantsEnv.positiveInt('PROTOCOL_METRICS_RPC_CHUNK_SAMPLE_RATE');
    if (parsed == null || parsed < 1) {
      return defaultProtocolMetricsRpcChunkSampleRate;
    }
    return parsed;
  }

  /// TTL for in-memory authorization decision cache entries on the SQL hot path.
  ///
  /// Override with env `AUTH_DECISION_CACHE_TTL_SECONDS` (15..600). Default 60s.
  static const int defaultAuthorizationDecisionCacheTtlSeconds = 60;

  static Duration get authorizationDecisionCacheTtl {
    final parsed = int.tryParse(ConnectionConstantsEnv.optional('AUTH_DECISION_CACHE_TTL_SECONDS') ?? '');
    if (parsed != null && parsed > 0) {
      return Duration(seconds: parsed.clamp(15, 600));
    }
    return const Duration(seconds: defaultAuthorizationDecisionCacheTtlSeconds);
  }

  /// GZIP payload size above which transport compress/decompress uses `compute`.
  ///
  /// Override with env `TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES` (positive integer bytes).
  static int get gzipIsolateThresholdBytes =>
      ConnectionConstantsEnv.positiveInt('TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES') ?? defaultGzipIsolateThresholdBytes;

  /// Transport-frame original size above which HMAC-SHA256 signing/verification
  /// is offloaded to a background isolate via `compute()`.
  ///
  /// HMAC is O(frame_size); for frames above this threshold the main-isolate
  /// signing cost is comparable to the gzip cost and worth offloading.
  /// Override with env `TRANSPORT_SIGNING_ISOLATE_THRESHOLD_BYTES`.
  static const int defaultSigningIsolateThresholdBytes = 64 * 1024;

  static int get signingIsolateThresholdBytes =>
      ConnectionConstantsEnv.positiveInt('TRANSPORT_SIGNING_ISOLATE_THRESHOLD_BYTES') ??
      defaultSigningIsolateThresholdBytes;

  /// Default credit advertised in
  /// `agent:capabilities.extensions.recommendedStreamPullWindowSize`.
  ///
  /// Raised from `1` to `12` so the hub starts with enough in-flight credits to
  /// keep streaming chunks moving without paying a round-trip per pull on LAN.
  /// The hub clamps this to its own ceiling and to `maxStreamPullWindowSize`
  /// (the agent advertises [maxBackpressureChunkQueueSize] as that ceiling).
  static const int defaultRecommendedStreamPullWindowSize = 12;

  /// Effective recommended pull window. Override with env
  /// `AGENT_STREAM_PULL_WINDOW_RECOMMENDED` (positive integer); clamped to
  /// `[1..maxBackpressureChunkQueueSize]`.
  static int get recommendedStreamPullWindowSize {
    final raw =
        ConnectionConstantsEnv.positiveInt('AGENT_STREAM_PULL_WINDOW_RECOMMENDED') ??
        defaultRecommendedStreamPullWindowSize;
    return raw.clamp(1, maxBackpressureChunkQueueSize);
  }

  /// Coalescing flush window for inbound `rpc:request_ack` debouncing. When a
  /// burst of `rpc:request` arrives (e.g. cross-agent `mergeAll`), individual
  /// acks are merged into a single `rpc:batch_ack` if more arrive before this
  /// timer elapses. See `plug_server/docs/plug_agente/03_performance_roadmap.md`
  /// item 3.
  static const Duration rpcAckCoalesceFlushInterval = Duration(milliseconds: 5);

  /// Maximum number of request ids coalesced into a single `rpc:batch_ack`.
  /// Mirrors the hub's `HUB_MAX_BATCH_SIZE` cap so the agent never produces a
  /// batch the hub cannot ingest in one frame.
  static const int rpcAckCoalesceMaxBatch = 32;
}
