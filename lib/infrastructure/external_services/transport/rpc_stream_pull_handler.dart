import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/stream_emitter_registry.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:result_dart/result_dart.dart';

/// Handles rpc:stream.pull credit release and backpressure stream emitters.
class RpcStreamPullHandler {
  RpcStreamPullHandler({
    required FeatureFlags featureFlags,
    required PayloadFrameCodec frameCodec,
    required RpcContractValidator contractValidator,
    required ProtocolConfig Function() protocolProvider,
    required Future<void> Function(String event, dynamic logicalPayload) emitEventAsync,
    required void Function(String direction, String event, dynamic data) logMessage,
  }) : _featureFlags = featureFlags,
       _frameCodec = frameCodec,
       _contractValidator = contractValidator,
       _emitEventAsync = emitEventAsync,
       _logMessage = logMessage,
       _streamEmitters = StreamEmitterRegistry(
         hardCeiling: ConnectionConstants.maxConcurrentRpcStreams,
         idleTtl: ConnectionConstants.rpcStreamEmitterMaxIdle,
         capProvider: () => protocolProvider().effectiveLimits.maxConcurrentStreams,
       );

  final FeatureFlags _featureFlags;
  final PayloadFrameCodec _frameCodec;
  final RpcContractValidator _contractValidator;
  final Future<void> Function(String event, dynamic logicalPayload) _emitEventAsync;
  final void Function(String direction, String event, dynamic data) _logMessage;
  final StreamEmitterRegistry _streamEmitters;

  IRpcStreamEmitter createStreamEmitter() {
    if (!_featureFlags.enableSocketBackpressure) {
      return _PassthroughRpcStreamEmitter(_emitValidatedStreamEvent);
    }
    return BackpressureStreamEmitter(
      emit: _emitValidatedStreamEvent,
      onRegister: (streamId, emitter) {
        final accepted = _streamEmitters.tryRegister(streamId, emitter);
        if (!accepted) {
          AppLogger.warning(
            'rpc stream emitter rejected: cap (effective='
            '${_streamEmitters.effectiveCap}, hard_ceiling='
            '${ConnectionConstants.maxConcurrentRpcStreams}) reached. '
            'stream_id=$streamId',
          );
        }
        return accepted;
      },
      onUnregister: _streamEmitters.unregister,
    );
  }

  void handlePull(dynamic data) {
    try {
      final payload = _frameCodec
          .decodeIncoming(
            data,
            sourceEvent: 'rpc:stream.pull',
          )
          .getOrThrow();
      if (payload is! Map<String, dynamic>) {
        return;
      }
      final pull = RpcStreamPull.fromJson(payload);
      _logMessage('INFO', 'rpc:stream.pull', {
        'stream_id': pull.streamId,
        'window_size': pull.windowSize,
      });
      final emitter = _streamEmitters.get(pull.streamId);
      if (emitter != null) {
        _streamEmitters.touch(pull.streamId);
        emitter.releaseChunks(pull.windowSize);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to handle rpc:stream.pull',
        error,
        stackTrace,
      );
    }
  }

  void dispose() {
    _streamEmitters.dispose();
  }

  Future<void> _emitValidatedStreamEvent(
    String event,
    Map<String, dynamic> payload,
  ) async {
    if (_featureFlags.enableSocketSchemaValidation) {
      Result<void> validation;
      if (event == 'rpc:chunk') {
        validation = _contractValidator.validateStreamChunk(payload);
      } else if (event == 'rpc:complete') {
        validation = _contractValidator.validateStreamComplete(payload);
      } else {
        validation = const Success(unit);
      }
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()! as domain.Failure;
        AppLogger.error('Invalid $event payload: ${failure.message}');
        return;
      }
    }

    await _emitEventAsync(event, payload);
  }
}

class _PassthroughRpcStreamEmitter implements IRpcStreamEmitter {
  _PassthroughRpcStreamEmitter(this._emitAsync);

  final Future<void> Function(String event, Map<String, dynamic> payload) _emitAsync;

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    await _emitAsync('rpc:chunk', chunk.toJson());
    return true;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {
    await _emitAsync('rpc:complete', complete.toJson());
  }
}
