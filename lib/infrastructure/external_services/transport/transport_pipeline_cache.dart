import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';

/// Caches send/receive [TransportPipeline] instances keyed by their effective
/// configuration so the transport client does not allocate a new pipeline per
/// emitted/decoded message.
///
/// - Send pipeline: at most one cached entry; rebuilt only when the negotiated
///   protocol or feature-flag combination changes (rare).
/// - Receive pipeline: bounded LRU map (default 16 entries) keyed by the
///   incoming [PayloadFrame] envelope; promotes on hit, evicts oldest on miss.
class TransportPipelineCache {
  TransportPipelineCache({
    required ProtocolConfig Function() protocolProvider,
    required bool Function() hasReceivedCapabilities,
    required FeatureFlags featureFlags,
    ProtocolMetricsCollector? metricsCollector,
    int maxReceiveEntries = defaultMaxReceiveEntries,
  }) : _protocolProvider = protocolProvider,
       _hasReceivedCapabilities = hasReceivedCapabilities,
       _featureFlags = featureFlags,
       _metricsCollector = metricsCollector,
       _maxReceiveEntries = maxReceiveEntries;

  /// Default cap kept in sync with
  /// [ConnectionConstants.receivePipelineCacheMaxEntries] so test fixtures and
  /// production share the same baseline. Override only in tests that exercise
  /// eviction behaviour.
  static const int defaultMaxReceiveEntries = ConnectionConstants.receivePipelineCacheMaxEntries;

  int evictionCount = 0;

  final ProtocolConfig Function() _protocolProvider;
  final bool Function() _hasReceivedCapabilities;
  final FeatureFlags _featureFlags;
  final ProtocolMetricsCollector? _metricsCollector;
  final int _maxReceiveEntries;

  TransportPipeline? _cachedSendPipeline;
  String _sendPipelineCacheKey = '';
  final Map<String, TransportPipeline> _receivePipelineByKey = {};

  TransportPipeline send() {
    final protocol = _protocolProvider();
    final hasCaps = _hasReceivedCapabilities();
    final negotiatedCmp = hasCaps ? protocol.compression : 'gzip';
    final String pipelineCompression;
    if (_featureFlags.outboundCompressionMode == OutboundCompressionMode.none || negotiatedCmp == 'none') {
      pipelineCompression = 'none';
    } else if (_featureFlags.outboundCompressionMode == OutboundCompressionMode.auto) {
      pipelineCompression = 'auto';
    } else {
      pipelineCompression = 'gzip';
    }
    final threshold = hasCaps ? protocol.compressionThreshold : _featureFlags.compressionThreshold;
    final cacheKey = '${protocol.encoding}|$pipelineCompression|$threshold|$hasCaps';
    final cached = _cachedSendPipeline;
    if (cached != null && _sendPipelineCacheKey == cacheKey) {
      return cached;
    }
    final pipeline = TransportPipeline(
      encoding: protocol.encoding,
      compression: pipelineCompression,
      compressionThreshold: threshold,
      protocol: protocol.protocol,
      metricsCollector: _metricsCollector,
    );
    _cachedSendPipeline = pipeline;
    _sendPipelineCacheKey = cacheKey;
    return pipeline;
  }

  TransportPipeline receive(PayloadFrame frame) {
    final protocol = _protocolProvider();
    final key =
        '${frame.enc}|${frame.cmp}|${frame.schemaVersion}|'
        '${protocol.compressionThreshold}';
    final hit = _receivePipelineByKey.remove(key);
    if (hit != null) {
      _receivePipelineByKey[key] = hit;
      return hit;
    }
    if (_receivePipelineByKey.length >= _maxReceiveEntries) {
      final evictedKey = _receivePipelineByKey.keys.first;
      _receivePipelineByKey.remove(evictedKey);
      evictionCount++;
      // Sampled debug log to flag heavy churn in production. The counter is
      // also exposed for the metrics collector to scrape.
      if (evictionCount <= 4 || evictionCount.isEven && evictionCount % 8 == 0) {
        AppLogger.debug(
          'transport pipeline cache eviction count=$evictionCount '
          'evicted_key=$evictedKey new_key=$key cap=$_maxReceiveEntries',
        );
      }
    }
    final pipeline = TransportPipeline(
      encoding: frame.enc,
      compression: frame.cmp,
      compressionThreshold: protocol.compressionThreshold,
      schemaVersion: frame.schemaVersion,
      protocol: protocol.protocol,
      metricsCollector: _metricsCollector,
    );
    _receivePipelineByKey[key] = pipeline;
    return pipeline;
  }

  void clearReceiveCache() {
    _receivePipelineByKey.clear();
  }

  void reset() {
    _cachedSendPipeline = null;
    _sendPipelineCacheKey = '';
    _receivePipelineByKey.clear();
  }

  int get receiveCacheSize => _receivePipelineByKey.length;
  Iterable<String> get receiveCacheKeys => _receivePipelineByKey.keys;
}
