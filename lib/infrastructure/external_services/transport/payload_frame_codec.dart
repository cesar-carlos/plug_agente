import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:result_dart/result_dart.dart';

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
    required bool Function() localShouldSignOutgoing,
    required bool Function() localRequiresIncomingSignature,
    PayloadSigner? payloadSigner,
    ProtocolMetricsCollector? metricsCollector,
  }) : _pipelineCache = pipelineCache,
       _protocolProvider = protocolProvider,
       _localCapabilitiesProvider = localCapabilitiesProvider,
       _hasReceivedCapabilities = hasReceivedCapabilities,
       _localShouldSignOutgoing = localShouldSignOutgoing,
       _localRequiresIncomingSignature = localRequiresIncomingSignature,
       _payloadSigner = payloadSigner,
       _metricsCollector = metricsCollector;

  final TransportPipelineCache _pipelineCache;
  final ProtocolConfig Function() _protocolProvider;
  final ProtocolCapabilities Function() _localCapabilitiesProvider;
  final bool Function() _hasReceivedCapabilities;
  final bool Function() _localShouldSignOutgoing;
  final bool Function() _localRequiresIncomingSignature;
  final PayloadSigner? _payloadSigner;
  final ProtocolMetricsCollector? _metricsCollector;
  final LogRateLimiter _warningLimiter = LogRateLimiter();

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
  bool get shouldSignTransportFrames {
    if (_payloadSigner == null) {
      return false;
    }
    if (!_hasReceivedCapabilities()) {
      return _localRequiresIncomingSignature();
    }
    final protocol = _protocolProvider();
    return _supportsNegotiatedSignatureAlgorithm(protocol) &&
        (_localShouldSignOutgoing() || protocol.signatureRequired);
  }

  /// Frames [logicalPayload] for transport. Returns the wire `Map<String,dynamic>`
  /// (frame JSON) on success. Failures are typed [domain.Failure] values for
  /// callers to map to RPC errors (typically internal error on outbound paths).
  Future<Result<Map<String, dynamic>>> prepareOutgoing({
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
      if (failure is domain.Failure) {
        return Failure(failure);
      }
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to frame $event payload for transport',
          cause: failure,
          context: {'event': event, 'rpc_error_code': RpcErrorCode.internalError},
        ),
      );
    }

    var frame = prepareResult.getOrThrow();
    if (frame.compressedSize > protocol.effectiveLimits.maxCompressedPayloadBytes) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: '$event payload exceeds negotiated transport limit after framing',
          context: {
            'event': event,
            'compressedSize': frame.compressedSize,
            'maxCompressedPayloadBytes': protocol.effectiveLimits.maxCompressedPayloadBytes,
            'rpc_error_code': RpcErrorCode.internalError,
          },
        ),
      );
    }
    if (frame.originalSize > protocol.effectiveLimits.maxDecodedPayloadBytes) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: '$event payload exceeds negotiated decoded payload limit',
          context: {
            'event': event,
            'originalSize': frame.originalSize,
            'maxDecodedPayloadBytes': protocol.effectiveLimits.maxDecodedPayloadBytes,
            'rpc_error_code': RpcErrorCode.internalError,
          },
        ),
      );
    }
    if (_hasReceivedCapabilities() && protocol.signatureRequired && !_supportsNegotiatedSignatureAlgorithm(protocol)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Cannot sign $event transport frame: no supported signature algorithm was negotiated',
          context: {
            'event': event,
            'rpc_error_code': RpcErrorCode.internalError,
          },
        ),
      );
    }
    if (shouldSignTransportFrames) {
      final signer = _payloadSigner;
      if (signer == null) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Attempted to sign $event transport frame without configured signer',
            context: {
              'event': event,
              'rpc_error_code': RpcErrorCode.internalError,
            },
          ),
        );
      }
      // Offload HMAC to a background isolate for large frames to avoid
      // blocking the main isolate during sustained high-throughput scenarios.
      final signingResult = frame.originalSize > ConnectionConstants.signingIsolateThresholdBytes
          ? await signer.signFrameAsync(frame)
          : signer.signFrameWithMetrics(frame);
      frame = frame.copyWith(
        signature: signingResult.signature.toJson(),
      );
      _recordSigningMetric(
        frame: frame,
        direction: 'sign',
        eventName: event,
        signDurationUs: signingResult.metrics.signDurationUs,
        canonicalizeDurationUs: signingResult.metrics.canonicalizeDurationUs,
      );
    }
    return Success(frame.toJson());
  }

  bool _supportsNegotiatedSignatureAlgorithm(ProtocolConfig protocol) =>
      protocol.signatureAlgorithms.contains(PayloadSigner.supportedAlgorithm);

  /// Synchronous decode used in hot paths (e.g. heartbeat ack).
  Result<dynamic> decodeIncoming(dynamic payload, {String? sourceEvent}) {
    return _decodeIncoming(
      payload,
      sourceEvent: sourceEvent,
      process: (PayloadFrame frame, ProtocolConfig protocol) => _pipelineCache
          .receive(frame)
          .receiveProcess(
            frame,
            maxCompressedBytes: protocol.effectiveLimits.maxCompressedPayloadBytes,
            maxOriginalBytes: protocol.effectiveLimits.maxDecodedPayloadBytes,
            maxInflationRatio: protocol.maxInflationRatio,
            metricEventName: sourceEvent,
          ),
    );
  }

  /// Async decode for incoming RPC requests/responses; offloads heavy gzip and
  /// JSON work to a background isolate (see `TransportPipeline.receiveProcessAsync`).
  Future<Result<dynamic>> decodeIncomingAsync(
    dynamic payload, {
    String? sourceEvent,
  }) async {
    final shapeResult = _ensureFrameShape(payload);
    if (shapeResult.isError()) {
      return Failure(shapeResult.exceptionOrNull()! as domain.Failure);
    }

    final protocol = _protocolProvider();
    try {
      final frame = PayloadFrame.fromJson(payload as Map<String, dynamic>);
      final validationResult = _validateFrameAgainstLocalCapabilities(frame, sourceEvent: sourceEvent);
      if (validationResult.isError()) {
        return Failure(validationResult.exceptionOrNull()! as domain.Failure);
      }

      final processed = await _pipelineCache
          .receive(frame)
          .receiveProcessAsync(
            frame,
            maxCompressedBytes: protocol.effectiveLimits.maxCompressedPayloadBytes,
            maxOriginalBytes: protocol.effectiveLimits.maxDecodedPayloadBytes,
            maxInflationRatio: protocol.maxInflationRatio,
            metricEventName: sourceEvent,
          );
      return _processedReceiveResult(processed, payload);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Failed to decode transport frame',
          cause: error,
          context: {
            'payloadType': payload.runtimeType.toString(),
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
  }

  Result<dynamic> _decodeIncoming(
    dynamic payload, {
    required Result<dynamic> Function(PayloadFrame frame, ProtocolConfig protocol) process,
    String? sourceEvent,
  }) {
    final shapeResult = _ensureFrameShape(payload);
    if (shapeResult.isError()) {
      return Failure(shapeResult.exceptionOrNull()! as domain.Failure);
    }

    final protocol = _protocolProvider();
    try {
      final frame = PayloadFrame.fromJson(payload as Map<String, dynamic>);
      final validationResult = _validateFrameAgainstLocalCapabilities(frame, sourceEvent: sourceEvent);
      if (validationResult.isError()) {
        return Failure(validationResult.exceptionOrNull()! as domain.Failure);
      }

      final processed = process(frame, protocol);
      return _processedReceiveResult(processed, payload);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Failed to decode transport frame',
          cause: error,
          context: {
            'payloadType': payload.runtimeType.toString(),
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
  }

  Result<dynamic> _processedReceiveResult(Result<dynamic> processed, dynamic payload) {
    if (processed.isError()) {
      final failure = processed.exceptionOrNull();
      if (failure is domain.Failure) {
        return Failure(failure);
      }
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Failed to decode transport frame',
          cause: failure,
          context: {
            'payloadType': payload.runtimeType.toString(),
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
    return Success(processed.getOrThrow() as Object);
  }

  Result<void> _ensureFrameShape(dynamic payload) {
    if (!looksLikePayloadFrame(payload)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Application payload must be a PayloadFrame',
          context: {
            'payloadType': payload.runtimeType.toString(),
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
    return const Success(unit);
  }

  Result<void> _validateFrameAgainstLocalCapabilities(
    PayloadFrame frame, {
    String? sourceEvent,
  }) {
    final localCapabilities = _localCapabilitiesProvider();
    final schemaVersionSegments = frame.schemaVersion.split('.');
    final majorVersion = schemaVersionSegments.length == 2 ? int.tryParse(schemaVersionSegments.first) : null;
    final minorVersion = schemaVersionSegments.length == 2 ? int.tryParse(schemaVersionSegments.last) : null;
    if (majorVersion != 1 || minorVersion == null) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unsupported PayloadFrame schema version: ${frame.schemaVersion}',
          context: {
            'schemaVersion': frame.schemaVersion,
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
    if (frame.contentType != 'application/json') {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unsupported PayloadFrame content type: ${frame.contentType}',
          context: {
            'contentType': frame.contentType,
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
    if (!localCapabilities.supportsEncoding(frame.enc)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unsupported payload encoding: ${frame.enc}',
          context: {
            'encoding': frame.enc,
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
    if (!localCapabilities.supportsCompression(frame.cmp)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unsupported payload compression: ${frame.cmp}',
          context: {
            'compression': frame.cmp,
            'rpc_error_code': RpcErrorCode.invalidPayload,
          },
        ),
      );
    }
    if (!_verifyFrameSignature(frame, sourceEvent: sourceEvent)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Invalid transport frame signature',
          context: {
            'request_id': frame.requestId,
            'transport_signature_invalid': true,
          },
        ),
      );
    }
    return const Success(unit);
  }

  bool _verifyFrameSignature(PayloadFrame frame, {String? sourceEvent}) {
    final signatureRequired = _hasReceivedCapabilities()
        ? _protocolProvider().signatureRequired
        : _localRequiresIncomingSignature();
    final sigJson = frame.signature;
    if (_payloadSigner == null) {
      if (sigJson != null) {
        if (_warningLimiter.shouldLog('signed_frame_without_signer')) {
          AppLogger.warning(
            'Received signed transport frame but no PayloadFrame signer is configured '
            '(count=${_warningLimiter.countFor('signed_frame_without_signer')})',
          );
        }
        return false;
      }
      return !signatureRequired;
    }
    if (sigJson == null) {
      return !signatureRequired;
    }
    final signature = PayloadSignature.fromJson(sigJson);
    final verificationResult = _payloadSigner.verifyFrameWithMetrics(frame, signature);
    _recordSigningMetric(
      frame: frame,
      direction: 'verify',
      eventName: sourceEvent,
      success: verificationResult.isValid,
      verifyDurationUs: verificationResult.metrics.verifyDurationUs,
      canonicalizeDurationUs: verificationResult.metrics.canonicalizeDurationUs,
    );
    return verificationResult.isValid;
  }

  void _recordSigningMetric({
    required PayloadFrame frame,
    required String direction,
    String? eventName,
    bool success = true,
    int? signDurationUs,
    int? verifyDurationUs,
    int? canonicalizeDurationUs,
  }) {
    final totalDurationUs = (signDurationUs ?? 0) + (verifyDurationUs ?? 0) + (canonicalizeDurationUs ?? 0);
    _metricsCollector?.record(
      ProtocolMetrics(
        timestamp: DateTime.now().toUtc(),
        protocol: _protocolProvider().protocol,
        encoding: frame.enc,
        compression: frame.cmp,
        originalSize: frame.originalSize,
        compressedSize: frame.compressedSize,
        direction: direction,
        eventName: eventName,
        success: success,
        totalDurationUs: totalDurationUs,
        signDurationUs: signDurationUs,
        verifyDurationUs: verifyDurationUs,
        canonicalizeDurationUs: canonicalizeDurationUs,
      ),
    );
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
