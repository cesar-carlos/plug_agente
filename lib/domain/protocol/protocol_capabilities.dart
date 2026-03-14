/// Protocol capabilities for negotiation between client and server.
///
/// Used during agent registration to determine which protocol version,
/// encoding, and compression methods are supported.
class ProtocolCapabilities {
  const ProtocolCapabilities({
    required this.protocols,
    required this.encodings,
    required this.compressions,
    this.extensions = const {},
    this.limits = const TransportLimits(),
  });

  factory ProtocolCapabilities.fromJson(Map<String, dynamic> json) {
    return ProtocolCapabilities(
      protocols: (json['protocols'] as List<dynamic>).cast<String>(),
      encodings: (json['encodings'] as List<dynamic>).cast<String>(),
      compressions: (json['compressions'] as List<dynamic>).cast<String>(),
      extensions: json['extensions'] as Map<String, dynamic>? ?? const {},
      limits: json['limits'] != null
          ? TransportLimits.fromJson(json['limits'] as Map<String, dynamic>)
          : const TransportLimits(),
    );
  }

  factory ProtocolCapabilities.defaultCapabilities() {
    return const ProtocolCapabilities(
      protocols: ['jsonrpc-v2'],
      encodings: ['json'],
      compressions: ['gzip', 'none'],
      extensions: {
        'batchSupport': true,
        'binaryPayload': false,
        'streamingResults': false,
        'plugProfile': 'plug-jsonrpc-profile/2.4',
        'orderedBatchResponses': true,
        'notificationNullIdCompatibility': true,
        'paginationModes': ['page-offset', 'cursor-keyset'],
        'traceContext': ['w3c-trace-context', 'legacy-trace-id'],
        'errorFormat': 'problem-details-inspired',
      },
    );
  }

  final List<String> protocols;
  final List<String> encodings;
  final List<String> compressions;
  final Map<String, dynamic> extensions;
  final TransportLimits limits;

  Map<String, dynamic> toJson() {
    return {
      'protocols': protocols,
      'encodings': encodings,
      'compressions': compressions,
      'extensions': extensions,
      'limits': limits.toJson(),
    };
  }

  /// Checks if a specific protocol is supported.
  bool supportsProtocol(String protocol) => protocols.contains(protocol);

  /// Checks if a specific encoding is supported.
  bool supportsEncoding(String encoding) => encodings.contains(encoding);

  /// Checks if a specific compression is supported.
  bool supportsCompression(String compression) =>
      compressions.contains(compression);

  /// Checks if JSON-RPC v2 is supported.
  bool get supportsJsonRpcV2 => protocols.contains('jsonrpc-v2');

  /// Checks if batch requests are supported.
  bool get supportsBatch => extensions['batchSupport'] as bool? ?? false;

  /// Checks if binary payload is supported.
  bool get supportsBinaryPayload =>
      extensions['binaryPayload'] as bool? ?? false;
}

/// Negotiated protocol configuration after handshake.
class ProtocolConfig {
  const ProtocolConfig({
    required this.protocol,
    required this.encoding,
    required this.compression,
    this.compressionThreshold = 1024,
    this.effectiveLimits = const TransportLimits(),
    this.negotiatedExtensions = const {},
  });

  final String protocol;
  final String encoding;
  final String compression;
  final int compressionThreshold;
  final TransportLimits effectiveLimits;
  final Map<String, dynamic> negotiatedExtensions;

  bool get isJsonRpcV2 => protocol == 'jsonrpc-v2';
  bool get usesCompression => compression != 'none';
  bool get usesBinaryPayload => encoding == 'msgpack';
}

/// Transport-level operational limits announced during handshake.
class TransportLimits {
  const TransportLimits({
    this.maxPayloadBytes = defaultMaxPayloadBytes,
    this.maxRows = defaultMaxRows,
    this.maxBatchSize = defaultMaxBatchSize,
    this.maxConcurrentStreams = defaultMaxConcurrentStreams,
    this.streamingChunkSize = defaultStreamingChunkSize,
    this.streamingRowThreshold = defaultStreamingRowThreshold,
  });

  factory TransportLimits.fromJson(Map<String, dynamic> json) {
    return TransportLimits(
      maxPayloadBytes:
          json['max_payload_bytes'] as int? ?? defaultMaxPayloadBytes,
      maxRows: json['max_rows'] as int? ?? defaultMaxRows,
      maxBatchSize: json['max_batch_size'] as int? ?? defaultMaxBatchSize,
      maxConcurrentStreams:
          json['max_concurrent_streams'] as int? ?? defaultMaxConcurrentStreams,
      streamingChunkSize:
          json['streaming_chunk_size'] as int? ?? defaultStreamingChunkSize,
      streamingRowThreshold:
          json['streaming_row_threshold'] as int? ??
          defaultStreamingRowThreshold,
    );
  }

  static const int defaultMaxPayloadBytes = 10 * 1024 * 1024; // 10 MB
  static const int defaultMaxRows = 50000;
  static const int defaultMaxBatchSize = 32;
  static const int defaultMaxConcurrentStreams = 1;
  static const int defaultStreamingChunkSize = 500;
  static const int defaultStreamingRowThreshold = 500;

  final int maxPayloadBytes;
  final int maxRows;
  final int maxBatchSize;
  final int maxConcurrentStreams;
  final int streamingChunkSize;
  final int streamingRowThreshold;

  TransportLimits negotiateWith(TransportLimits other) {
    return TransportLimits(
      maxPayloadBytes: maxPayloadBytes < other.maxPayloadBytes
          ? maxPayloadBytes
          : other.maxPayloadBytes,
      maxRows: maxRows < other.maxRows ? maxRows : other.maxRows,
      maxBatchSize: maxBatchSize < other.maxBatchSize
          ? maxBatchSize
          : other.maxBatchSize,
      maxConcurrentStreams: maxConcurrentStreams < other.maxConcurrentStreams
          ? maxConcurrentStreams
          : other.maxConcurrentStreams,
      streamingChunkSize: streamingChunkSize < other.streamingChunkSize
          ? streamingChunkSize
          : other.streamingChunkSize,
      streamingRowThreshold: streamingRowThreshold < other.streamingRowThreshold
          ? streamingRowThreshold
          : other.streamingRowThreshold,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'max_payload_bytes': maxPayloadBytes,
      'max_rows': maxRows,
      'max_batch_size': maxBatchSize,
      'max_concurrent_streams': maxConcurrentStreams,
      'streaming_chunk_size': streamingChunkSize,
      'streaming_row_threshold': streamingRowThreshold,
    };
  }
}
