import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

/// Encodes outgoing logical payloads into [PayloadFrame] envelopes and decodes
/// incoming envelopes back into the application-level Map/List structure.
///
/// Centralises the framing rules:
///   * Outgoing: compression/encoding via [TransportPipelineCache], optional
///     transport-level HMAC signature, and the negotiated payload size limits.
///   * Incoming: signature verification, encoding/compression capability check,
///     and decompression with inflation-ratio guards.
class PayloadFrameCodec {
  PayloadFrameCodec({
    required TransportPipelineCache pipelineCache,
    required ProtocolConfig Function() protocolProvider,
    required ProtocolCapabilities Function() localCapabilitiesProvider,
    required bool Function() hasReceivedCapabilities,
    required bool Function() localSignatureRequired,
    PayloadSigner? payloadSigner,
  }) : _pipelineCache = pipelineCache,
       _protocolProvider = protocolProvider,
       _localCapabilitiesProvider = localCapabilitiesProvider,
       _hasReceivedCapabilities = hasReceivedCapabilities,
       _localSignatureRequired = localSignatureRequired,
       _payloadSigner = payloadSigner;

  final TransportPipelineCache _pipelineCache;
  final ProtocolConfig Function() _protocolProvider;
  final ProtocolCapabilities Function() _localCapabilitiesProvider;
  final bool Function() _hasReceivedCapabilities;
  final bool Function() _localSignatureRequired;
  final PayloadSigner? _payloadSigner;

  /// Returns `true` when [payload] looks like a [PayloadFrame] envelope
  /// (cheap structural sniff, used to differentiate transport frames from
  /// legacy raw JSON-RPC payloads).
  bool looksLikePayloadFrame(dynamic payload) {
    return payload is Map<String, dynamic> &&
        payload.containsKey('schemaVersion') &&
        payload.containsKey('enc') &&
        payload.containsKey('cmp') &&
        payload.containsKey('payload') &&
        payload.containsKey('originalSize') &&
        payload.containsKey('compressedSize');
  }

  /// Whether outgoing transport frames must carry an HMAC signature.
  bool get shouldSignTransportFrames =>
      _payloadSigner != null &&
      (_localSignatureRequired() || (_hasReceivedCapabilities() && _protocolProvider().signatureRequired));

  /// Frames [logicalPayload] for transport. Returns the wire `Map<String,dynamic>`
  /// (frame JSON) on success or `null` if the payload exceeds the negotiated
  /// limits, signing is required but unavailable, or the pipeline fails.
  /// Errors are logged through [AppLogger] before returning `null`.
  Future<Map<String, dynamic>?> prepareOutgoing({
    required String event,
    required dynamic logicalPayload,
  }) async {
    final protocol = _protocolProvider();
    final prepareResult = await _pipelineCache.send().prepareSendAsync(
      logicalPayload,
      traceId: _extractTraceId(logicalPayload),
      requestId: _extractRequestId(logicalPayload),
      metricEventName: event,
    );
    if (prepareResult.isError()) {
      final failure = prepareResult.exceptionOrNull();
      AppLogger.error(
        'Failed to frame $event payload for transport: $failure',
      );
      return null;
    }

    var frame = prepareResult.getOrThrow();
    if (frame.compressedSize > protocol.effectiveLimits.maxCompressedPayloadBytes) {
      AppLogger.error(
        '$event payload exceeds negotiated transport limit after framing',
      );
      return null;
    }
    if (frame.originalSize > protocol.effectiveLimits.maxDecodedPayloadBytes) {
      AppLogger.error(
        '$event payload exceeds negotiated decoded payload limit',
      );
      return null;
    }
    if (shouldSignTransportFrames) {
      final signer = _payloadSigner;
      if (signer == null) {
        AppLogger.error(
          'Attempted to sign $event transport frame without configured signer',
        );
        return null;
      }
      frame = frame.copyWith(
        signature: signer.signFrame(frame).toJson(),
      );
    }
    return frame.toJson();
  }

  /// Synchronous decode used in hot paths (e.g. heartbeat ack). Throws
  /// [domain.ValidationFailure] when the envelope is malformed, the encoding/
  /// compression isn't supported locally, the signature is invalid, or
  /// decompression fails.
  dynamic decodeIncoming(dynamic payload, {String? sourceEvent}) {
    _ensureFrameShape(payload);
    final protocol = _protocolProvider();
    try {
      final frame = PayloadFrame.fromJson(payload as Map<String, dynamic>);
      _validateFrameAgainstLocalCapabilities(frame);
      final processed = _pipelineCache
          .receive(frame)
          .receiveProcess(
            frame,
            maxCompressedBytes: protocol.effectiveLimits.maxCompressedPayloadBytes,
            maxOriginalBytes: protocol.effectiveLimits.maxDecodedPayloadBytes,
            maxInflationRatio: protocol.maxInflationRatio,
            metricEventName: sourceEvent,
          );
      if (processed.isError()) {
        throw processed.exceptionOrNull()! as domain.Failure;
      }
      return processed.getOrThrow();
    } on domain.Failure {
      rethrow;
    } on Exception catch (error) {
      throw domain.ValidationFailure.withContext(
        message: 'Failed to decode transport frame',
        cause: error,
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }
  }

  /// Async decode for incoming RPC requests/responses; offloads heavy gzip and
  /// JSON work to a background isolate (see `TransportPipeline.receiveProcessAsync`).
  Future<dynamic> decodeIncomingAsync(
    dynamic payload, {
    String? sourceEvent,
  }) async {
    _ensureFrameShape(payload);
    final protocol = _protocolProvider();
    try {
      final frame = PayloadFrame.fromJson(payload as Map<String, dynamic>);
      _validateFrameAgainstLocalCapabilities(frame);
      final processed = await _pipelineCache
          .receive(frame)
          .receiveProcessAsync(
            frame,
            maxCompressedBytes: protocol.effectiveLimits.maxCompressedPayloadBytes,
            maxOriginalBytes: protocol.effectiveLimits.maxDecodedPayloadBytes,
            maxInflationRatio: protocol.maxInflationRatio,
            metricEventName: sourceEvent,
          );
      if (processed.isError()) {
        throw processed.exceptionOrNull()! as domain.Failure;
      }
      return processed.getOrThrow();
    } on domain.Failure {
      rethrow;
    } on Exception catch (error) {
      throw domain.ValidationFailure.withContext(
        message: 'Failed to decode transport frame',
        cause: error,
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }
  }

  void _ensureFrameShape(dynamic payload) {
    if (!looksLikePayloadFrame(payload)) {
      throw domain.ValidationFailure.withContext(
        message: 'Application payload must be a PayloadFrame',
        context: {'payloadType': payload.runtimeType.toString()},
      );
    }
  }

  void _validateFrameAgainstLocalCapabilities(PayloadFrame frame) {
    final localCapabilities = _localCapabilitiesProvider();
    if (!localCapabilities.supportsEncoding(frame.enc)) {
      throw domain.ValidationFailure.withContext(
        message: 'Unsupported payload encoding: ${frame.enc}',
        context: {'encoding': frame.enc},
      );
    }
    if (!localCapabilities.supportsCompression(frame.cmp)) {
      throw domain.ValidationFailure.withContext(
        message: 'Unsupported payload compression: ${frame.cmp}',
        context: {'compression': frame.cmp},
      );
    }
    if (!_verifyFrameSignature(frame)) {
      throw domain.ValidationFailure.withContext(
        message: 'Invalid transport frame signature',
        context: {
          'request_id': frame.requestId,
          'transport_signature_invalid': true,
        },
      );
    }
  }

  bool _verifyFrameSignature(PayloadFrame frame) {
    final signatureRequired = _hasReceivedCapabilities()
        ? _protocolProvider().signatureRequired
        : _localSignatureRequired();
    if (_payloadSigner == null) {
      return !signatureRequired;
    }
    final sigJson = frame.signature;
    if (sigJson == null) {
      return !signatureRequired;
    }
    final signature = PayloadSignature.fromJson(sigJson);
    return _payloadSigner.verifyFrame(frame, signature);
  }

  String? _extractTraceId(dynamic payload) {
    if (payload is! Map<String, dynamic>) return null;
    final meta = payload['meta'];
    if (meta is! Map<String, dynamic>) {
      return payload['trace_id'] as String?;
    }
    return meta['trace_id'] as String?;
  }

  String? _extractRequestId(dynamic payload) {
    if (payload is! Map<String, dynamic>) return null;
    final requestId = payload['id'] ?? payload['request_id'];
    if (requestId != null) {
      return requestId.toString();
    }
    final meta = payload['meta'];
    if (meta is Map<String, dynamic>) {
      final metaRequestId = meta['request_id'];
      if (metaRequestId != null) {
        return metaRequestId.toString();
      }
    }
    return null;
  }
}
