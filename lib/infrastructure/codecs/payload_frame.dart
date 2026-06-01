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
    this.signature,
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
      signature: json['signature'] as Map<String, dynamic>?,
    );
  }

  /// Schema version (e.g., '1.0').
  final String schemaVersion;

  /// Encoding format. Wire contract uses `json` only (`enc` must be `json`).
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

  /// Optional transport-level signature.
  final Map<String, dynamic>? signature;

  Map<String, dynamic> toJson() {
    return _toMap(payload);
  }

  /// Returns the Socket.IO wire map with the binary payload represented as a
  /// [ByteBuffer]. The Socket.IO client treats both [Uint8List] and
  /// [ByteBuffer] as binary attachments, but [Uint8List.toString] expands every
  /// byte when the package formats packets for debug logging. [ByteBuffer]
  /// keeps that synchronous formatting bounded without changing the wire shape.
  Map<String, dynamic> toSocketPayload() {
    return _toMap(_socketPayload(payload));
  }

  Map<String, dynamic> _toMap(dynamic payloadValue) {
    return {
      'schemaVersion': schemaVersion,
      'enc': enc,
      'cmp': cmp,
      'contentType': contentType,
      'originalSize': originalSize,
      'compressedSize': compressedSize,
      'payload': payloadValue,
      if (traceId != null) 'traceId': traceId,
      if (requestId != null) 'requestId': requestId,
      if (signature != null) 'signature': signature,
    };
  }

  PayloadFrame copyWith({
    String? schemaVersion,
    String? enc,
    String? cmp,
    String? contentType,
    int? originalSize,
    int? compressedSize,
    dynamic payload,
    String? traceId,
    String? requestId,
    Map<String, dynamic>? signature,
    bool clearSignature = false,
  }) {
    return PayloadFrame(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      enc: enc ?? this.enc,
      cmp: cmp ?? this.cmp,
      contentType: contentType ?? this.contentType,
      originalSize: originalSize ?? this.originalSize,
      compressedSize: compressedSize ?? this.compressedSize,
      payload: payload ?? this.payload,
      traceId: traceId ?? this.traceId,
      requestId: requestId ?? this.requestId,
      signature: clearSignature ? null : (signature ?? this.signature),
    );
  }

  bool get isCompressed => cmp != 'none';
  bool get isBinary => payload is ByteBuffer || payload is Uint8List || payload is List<int>;
  double get compressionRatio => compressedSize / originalSize;

  static dynamic _socketPayload(dynamic payload) {
    if (payload is ByteBuffer) {
      return payload;
    }
    if (payload is Uint8List) {
      return _asTightByteBuffer(payload);
    }
    if (payload is List<int>) {
      return Uint8List.fromList(payload).buffer;
    }
    return payload;
  }

  static ByteBuffer _asTightByteBuffer(Uint8List bytes) {
    if (bytes.offsetInBytes == 0 && bytes.lengthInBytes == bytes.buffer.lengthInBytes) {
      return bytes.buffer;
    }
    return Uint8List.fromList(bytes).buffer;
  }
}
