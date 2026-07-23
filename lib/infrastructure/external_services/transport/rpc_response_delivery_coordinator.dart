import 'dart:async';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/protocol/delivery_guarantee.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const Set<String> sqlRpcResponseAckBypassMethods = <String>{
  'sql.execute',
  'sql.executeBatch',
};

/// Prepares, validates, and delivers outbound `rpc:response` frames.
final class RpcResponseDeliveryCoordinator {
  RpcResponseDeliveryCoordinator({
    required RpcResponsePreparer responsePreparer,
    required Future<Result<dynamic>> Function(String event, dynamic logicalPayload) prepareOutgoingPayload,
    required void Function(String direction, String event, dynamic data) logMessage,
    required bool Function() deliveryGuaranteesEnabled,
    required io.Socket? Function() activeSocket,
    required int Function() connectGeneration,
    required MetricsCollector? metricsCollector,
    required Future<void> Function(dynamic requestId) emitInternalErrorResponse,
    void Function({required String event, required dynamic logicalPayload})? onValidatedPayload,
    Duration? responseAckTimeout,
  }) : _responsePreparer = responsePreparer,
       _prepareOutgoingPayload = prepareOutgoingPayload,
       _logMessage = logMessage,
       _deliveryGuaranteesEnabled = deliveryGuaranteesEnabled,
       _activeSocket = activeSocket,
       _connectGeneration = connectGeneration,
       _metricsCollector = metricsCollector,
       _emitInternalErrorResponse = emitInternalErrorResponse,
       _onValidatedPayload = onValidatedPayload,
       _responseAckTimeout = responseAckTimeout ?? DeliveryGuaranteeConfig.responseAckTimeout;

  final RpcResponsePreparer _responsePreparer;
  final Future<Result<dynamic>> Function(String event, dynamic logicalPayload) _prepareOutgoingPayload;
  final void Function(String direction, String event, dynamic data) _logMessage;
  final bool Function() _deliveryGuaranteesEnabled;
  final io.Socket? Function() _activeSocket;
  final int Function() _connectGeneration;
  final MetricsCollector? _metricsCollector;
  final Future<void> Function(dynamic requestId) _emitInternalErrorResponse;
  final void Function({required String event, required dynamic logicalPayload})? _onValidatedPayload;
  final Duration _responseAckTimeout;

  Future<void> emit(
    dynamic responseData, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) async {
    final prepared = responseData is List<RpcResponse>
        ? responseData.map(_responsePreparer.prepareForSend).toList()
        : _responsePreparer.prepareForSend(responseData as RpcResponse);
    final validatedResult = _responsePreparer.validateOutgoing(
      prepared,
      methodsById: methodsById,
    );
    if (validatedResult.isError()) {
      AppLogger.warning(
        'rpc:response outgoing validation failed catastrophically - emitting internal error',
        validatedResult.exceptionOrNull(),
      );
      final requestId = extractResponseId(responseData);
      await _emitInternalErrorResponse(requestId);
      return;
    }
    final validatedPayload = validatedResult.getOrThrow();
    _onValidatedPayload?.call(event: 'rpc:response', logicalPayload: validatedPayload);

    final outgoingResult = await _prepareOutgoingPayload(
      'rpc:response',
      validatedPayload,
    );
    if (outgoingResult.isError()) {
      AppLogger.warning(
        'rpc:response pipeline encoding failed - emitting internal error',
        outgoingResult.exceptionOrNull(),
      );
      final requestId = extractResponseId(responseData);
      await _emitInternalErrorResponse(requestId);
      return;
    }
    final outgoingPayload = outgoingResult.getOrThrow();

    final deliverySocket = _activeSocket();
    if (deliverySocket == null) {
      _metricsCollector?.recordRpcResponseEmitSkippedDisconnected();
      AppLogger.warning('Skipping rpc:response emit because socket is disconnected');
      return;
    }
    final shouldSkipSocketAck = _shouldEmitRpcResponseWithoutSocketAck(methodsById);
    if (!_deliveryGuaranteesEnabled() || shouldSkipSocketAck) {
      try {
        deliverySocket.emit('rpc:response', outgoingPayload);
      } on Object catch (error, stackTrace) {
        _metricsCollector?.recordRpcResponseEmitFailure();
        AppLogger.error(
          'Socket emit failed for rpc:response',
          error,
          stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
      _logMessage('SENT', 'rpc:response', validatedPayload);
      if (_deliveryGuaranteesEnabled() && shouldSkipSocketAck) {
        _recordSkippedSqlRpcResponseAck(methodsById);
      }
      return;
    }

    _logMessage('SENT', 'rpc:response', validatedPayload);
    final deliveryGeneration = _connectGeneration();
    unawaited(
      _deliverWithAck(
        outgoingPayload,
        socket: deliverySocket,
        connectGeneration: deliveryGeneration,
      ).catchError((Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Unhandled rpc:response ACK delivery failure',
          error,
          stackTrace,
        );
      }),
    );
  }

  static dynamic extractResponseId(dynamic responseData) {
    if (responseData is RpcResponse) {
      return responseData.id;
    }
    if (responseData is List<RpcResponse> && responseData.isNotEmpty) {
      return responseData.first.id;
    }
    return null;
  }

  bool _shouldEmitRpcResponseWithoutSocketAck(Map<Object?, String> methodsById) {
    return methodsById.values.any(sqlRpcResponseAckBypassMethods.contains);
  }

  void _recordSkippedSqlRpcResponseAck(Map<Object?, String> methodsById) {
    if (methodsById.values.any((method) => method == 'sql.executeBatch')) {
      _metricsCollector?.recordRpcResponseAckSkippedSqlExecuteBatch();
      AppLogger.info('rpc:response emitted without Socket.IO ACK for sql.executeBatch response');
      return;
    }
    if (methodsById.values.any((method) => method == 'sql.execute')) {
      _metricsCollector?.recordRpcResponseAckSkippedSqlExecute();
      AppLogger.info('rpc:response emitted without Socket.IO ACK for sql.execute response');
    }
  }

  Future<void> _deliverWithAck(
    dynamic outgoingPayload, {
    required io.Socket socket,
    required int connectGeneration,
  }) async {
    const maxRetries = DeliveryGuaranteeConfig.maxResponseRetries;
    const totalAttempts = maxRetries + 1;

    for (var attempt = 0; attempt < totalAttempts; attempt++) {
      if (!_isDeliveryCurrent(socket: socket, connectGeneration: connectGeneration)) {
        _metricsCollector?.recordRpcResponseAckAbortedConnectionChange();
        AppLogger.info(
          'rpc:response ack delivery aborted due connection generation change',
        );
        return;
      }
      try {
        await _emitWithTolerantAck(
          socket,
          outgoingPayload,
          connectGeneration: connectGeneration,
        );
        _metricsCollector?.recordRpcResponseAckDelivered();
        return;
      } on _AckDeliveryAborted {
        _metricsCollector?.recordRpcResponseAckAbortedConnectionChange();
        AppLogger.info(
          'rpc:response ack delivery aborted due connection generation change',
        );
        return;
      } on Object catch (error, stackTrace) {
        if (!_isDeliveryCurrent(socket: socket, connectGeneration: connectGeneration)) {
          _metricsCollector?.recordRpcResponseAckAbortedConnectionChange();
          AppLogger.info(
            'rpc:response ack delivery aborted due connection generation change',
          );
          return;
        }
        final remaining = totalAttempts - attempt - 1;
        if (remaining > 0) {
          _metricsCollector?.recordRpcResponseAckRetry();
          AppLogger.warning(
            'rpc:response ack timeout, retrying (${attempt + 1}/$maxRetries)',
            error,
            stackTrace,
          );
        } else {
          _metricsCollector?.recordRpcResponseAckFallbackWithoutAck();
          AppLogger.warning(
            'rpc:response ack failed after $maxRetries retries, sending without ack',
            error,
            stackTrace,
          );
          socket.emit('rpc:response', outgoingPayload);
        }
      }
    }
  }

  bool _isDeliveryCurrent({
    required io.Socket socket,
    required int connectGeneration,
  }) {
    return _activeSocket() == socket && _connectGeneration() == connectGeneration;
  }

  /// Own timeout + [io.Socket.emitWithAck] with a 0-arg-tolerant callback.
  ///
  /// Avoids `socket.timeout(...).emitWithAckAsync(...)`: socket_io_client 3.1.4
  /// wraps timed acks as `(args)` and `onack` does `Function.apply(ack, [])` for
  /// empty hub ACKs (`data: []`), which throws and leaves the Completer hanging.
  Future<void> _emitWithTolerantAck(
    io.Socket socket,
    dynamic outgoingPayload, {
    required int connectGeneration,
  }) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;
    Timer? generationPoll;

    void completeOnce(void Function() complete) {
      if (completer.isCompleted) {
        return;
      }
      timeoutTimer?.cancel();
      generationPoll?.cancel();
      complete();
    }

    // Optional positional so empty hub ACK (`Function.apply(ack, [])`) succeeds.
    void onAck([dynamic _]) {
      completeOnce(completer.complete);
    }

    timeoutTimer = Timer(_responseAckTimeout, () {
      completeOnce(
        () => completer.completeError(
          TimeoutException(
            'rpc:response Socket.IO ACK timed out',
            _responseAckTimeout,
          ),
        ),
      );
    });

    generationPoll = Timer.periodic(DeliveryGuaranteeConfig.responseAckGenerationPollInterval, (_) {
      if (!_isDeliveryCurrent(socket: socket, connectGeneration: connectGeneration)) {
        completeOnce(
          () => completer.completeError(const _AckDeliveryAborted()),
        );
      }
    });

    try {
      socket.emitWithAck('rpc:response', outgoingPayload, ack: onAck);
    } on Object catch (error, stackTrace) {
      timeoutTimer.cancel();
      generationPoll.cancel();
      Error.throwWithStackTrace(error, stackTrace);
    }

    await completer.future;
  }
}

/// Internal signal that ACK wait was cancelled because the socket generation changed.
final class _AckDeliveryAborted implements Exception {
  const _AckDeliveryAborted();
}
