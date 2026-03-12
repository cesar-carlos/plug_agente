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
  });

  factory ProtocolCapabilities.fromJson(Map<String, dynamic> json) {
    return ProtocolCapabilities(
      protocols: (json['protocols'] as List<dynamic>).cast<String>(),
      encodings: (json['encodings'] as List<dynamic>).cast<String>(),
      compressions: (json['compressions'] as List<dynamic>).cast<String>(),
      extensions: json['extensions'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Default capabilities for the agent (v2 preferred, v1 fallback).
  factory ProtocolCapabilities.defaultCapabilities() {
    return const ProtocolCapabilities(
      protocols: ['jsonrpc-v2', 'legacy-envelope-v1'],
      encodings: ['json', 'msgpack'],
      compressions: ['gzip', 'none'],
      extensions: {
        'batchSupport': true,
        'binaryPayload': true,
        'streamingResults': false,
      },
    );
  }

  /// Legacy-only capabilities (for fallback compatibility).
  factory ProtocolCapabilities.legacyOnly() {
    return const ProtocolCapabilities(
      protocols: ['legacy-envelope-v1'],
      encodings: ['json'],
      compressions: ['none'],
      extensions: {
        'batchSupport': false,
        'binaryPayload': false,
      },
    );
  }

  /// Supported protocol versions (e.g., 'jsonrpc-v2', 'legacy-envelope-v1').
  final List<String> protocols;

  /// Supported encoding formats (e.g., 'json', 'msgpack').
  final List<String> encodings;

  /// Supported compression algorithms (e.g., 'gzip', 'none').
  final List<String> compressions;

  /// Optional extension features.
  final Map<String, dynamic> extensions;

  Map<String, dynamic> toJson() {
    return {
      'protocols': protocols,
      'encodings': encodings,
      'compressions': compressions,
      'extensions': extensions,
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

  /// Checks if legacy envelope v1 is supported.
  bool get supportsLegacyV1 => protocols.contains('legacy-envelope-v1');

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
  });

  /// Selected protocol version.
  final String protocol;

  /// Selected encoding format.
  final String encoding;

  /// Selected compression algorithm.
  final String compression;

  /// Minimum payload size (bytes) to trigger compression.
  final int compressionThreshold;

  bool get isJsonRpcV2 => protocol == 'jsonrpc-v2';
  bool get isLegacyV1 => protocol == 'legacy-envelope-v1';
  bool get usesCompression => compression != 'none';
  bool get usesBinaryPayload => encoding == 'msgpack';
}
