import 'dart:typed_data';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_constants.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_receive.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_send.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:uuid/uuid.dart';

export 'transport_pipeline_constants.dart';
export 'transport_pipeline_isolate.dart';

/// Transport pipeline for encoding/compressing and decoding/decompressing payloads.
///
/// Handles the complete bidirectional flow:
/// Send: data -> encode -> compress -> frame
/// Receive: frame -> decompress -> decode -> data
class TransportPipeline with TransportPipelineSend, TransportPipelineReceive {
  TransportPipeline({
    required this.encoding,
    required this.compression,
    this.compressionThreshold = defaultTransportCompressionThresholdBytes,
    this.maxInflationRatio = defaultTransportMaxInflationRatio,
    this.gzipIsolateThresholdBytes = ConnectionConstants.defaultGzipIsolateThresholdBytes,
    this.schemaVersion = '1.0',
    this.protocol = 'jsonrpc-v2',
    this.metricsCollector,
    Uuid? uuid,
  }) : pipelineUuid = uuid ?? const Uuid();

  /// Selected encoding format.
  @override
  final String encoding;

  /// Send-path compression: `none`, `gzip`, or `auto` (try GZIP; use wire `gzip`
  /// only if smaller than raw UTF-8). Received frames only use `none`/`gzip`.
  @override
  final String compression;

  /// Minimum payload size (bytes) to trigger compression.
  @override
  final int compressionThreshold;

  /// Maximum decoded/compressed ratio accepted by peers for gzip frames.
  @override
  final double maxInflationRatio;

  /// Minimum payload size (bytes) to run GZIP compress/decompress in a background isolate.
  @override
  final int gzipIsolateThresholdBytes;

  /// Schema version for the payload frame.
  @override
  final String schemaVersion;

  /// Logical transport protocol associated with the current pipeline instance.
  @override
  final String protocol;

  /// Optional collector for transport telemetry.
  @override
  final ProtocolMetricsCollector? metricsCollector;

  @override
  final Uuid pipelineUuid;

  /// Creates a frame from raw bytes (for legacy compatibility).
  PayloadFrame frameFromBytes(Uint8List bytes, {String? requestId}) {
    return PayloadFrame(
      schemaVersion: schemaVersion,
      enc: encoding,
      cmp: 'none',
      contentType: PayloadCodecFactory.getCodec(encoding).contentType,
      originalSize: bytes.length,
      compressedSize: bytes.length,
      payload: bytes,
      traceId: pipelineUuid.v4(),
      requestId: requestId,
    );
  }
}
