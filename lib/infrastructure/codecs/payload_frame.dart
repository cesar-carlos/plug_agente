import 'dart:typed_data';

/// Payload frame with metadata for transport.
///
/// Contains encoding, compression, and size information for efficient
/// bidirectional communication over Socket.IO.
class PayloadFrame {
  const PayloadFrame({
    required this.schemaVersion,
    required this.enc,
    required this.cmp,
    required this.contentType,
    required this.originalSize,
    required this.compressedSize,
    required this.payload,
    this.traceId,
    this.requestId,
  });

  factory PayloadFrame.fromJson(Map<String, dynamic> json) {
    return PayloadFrame(
      schemaVersion: json['schemaVersion'] as String,
      enc: json['enc'] as String,
      cmp: json['cmp'] as String,
      contentType: json['contentType'] as String,
      originalSize: json['originalSize'] as int,
      compressedSize: json['compressedSize'] as int,
      payload: json['payload'],
      traceId: json['traceId'] as String?,
      requestId: json['requestId'] as String?,
    );
  }

  /// Schema version (e.g., '1.0').
  final String schemaVersion;

  /// Encoding format: 'json' or 'msgpack'.
  final String enc;

  /// Compression algorithm: 'none' or 'gzip'.
  final String cmp;

  /// Content type (e.g., 'application/json', 'application/octet-stream').
  final String contentType;

  /// Original payload size in bytes before compression.
  final int originalSize;

  /// Compressed payload size in bytes (equals originalSize if cmp='none').
  final int compressedSize;

  /// The actual payload data (can be bytes or structured data).
  final dynamic payload;

  /// Optional trace ID for distributed tracing.
  final String? traceId;

  /// Optional request ID for correlation.
  final String? requestId;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'enc': enc,
      'cmp': cmp,
      'contentType': contentType,
      'originalSize': originalSize,
      'compressedSize': compressedSize,
      'payload': payload,
      if (traceId != null) 'traceId': traceId,
      if (requestId != null) 'requestId': requestId,
    };
  }

  bool get isCompressed => cmp != 'none';
  bool get isBinary => payload is Uint8List || payload is List<int>;
  double get compressionRatio => compressedSize / originalSize;
}
