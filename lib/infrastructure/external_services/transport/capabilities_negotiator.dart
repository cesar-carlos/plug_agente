import 'dart:async';

import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

/// Outcome reported by [CapabilitiesNegotiator.handleEnvelope] so the transport
/// client can react to the negotiation result without owning the
/// agent:capabilities flow.
sealed class CapabilitiesNegotiationOutcome {
  const CapabilitiesNegotiationOutcome();
}

/// Successful negotiation. The transport client should commit the new protocol
/// (already provided), trigger heartbeat, optionally emit `agent:ready`, and
/// notify hub-lifecycle listeners about reconnect completion.
class CapabilitiesNegotiationSuccess extends CapabilitiesNegotiationOutcome {
  const CapabilitiesNegotiationSuccess({
    required this.negotiatedProtocol,
    required this.wasPostReconnect,
  });

  final ProtocolConfig negotiatedProtocol;
  final bool wasPostReconnect;
}

/// Negotiation failed; the transport client must tear the socket down and
/// trigger the reconnection callback.
class CapabilitiesNegotiationFailure extends CapabilitiesNegotiationOutcome {
  const CapabilitiesNegotiationFailure({
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace stackTrace;
}

/// Encapsulates the agent:register / agent:capabilities handshake, including
/// the `capabilitiesTimeout` re-register policy.
///
/// Stays free of `io.Socket`: the transport client provides callbacks for
/// emitting frames and decoding inbound payloads.
class CapabilitiesNegotiator {
  CapabilitiesNegotiator({
    required ProtocolNegotiator negotiator,
    required FeatureFlags featureFlags,
    required RpcContractValidator contractValidator,
    required ProtocolCapabilities Function() localCapabilitiesProvider,
    required String Function() agentIdProvider,
    required Future<void> Function(String event, dynamic payload) emit,
    required dynamic Function(dynamic payload, {String? sourceEvent}) decodeIncoming,
    required void Function() onTimeoutReconnect,
    PayloadSigner? payloadSigner,
  }) : _negotiator = negotiator,
       _featureFlags = featureFlags,
       _contractValidator = contractValidator,
       _localCapabilitiesProvider = localCapabilitiesProvider,
       _agentIdProvider = agentIdProvider,
       _emit = emit,
       _decodeIncoming = decodeIncoming,
       _onTimeoutReconnect = onTimeoutReconnect,
       _payloadSigner = payloadSigner;

  final ProtocolNegotiator _negotiator;
  final FeatureFlags _featureFlags;
  final RpcContractValidator _contractValidator;
  final ProtocolCapabilities Function() _localCapabilitiesProvider;
  final String Function() _agentIdProvider;
  final Future<void> Function(String event, dynamic payload) _emit;
  final dynamic Function(dynamic payload, {String? sourceEvent}) _decodeIncoming;
  final void Function() _onTimeoutReconnect;
  final PayloadSigner? _payloadSigner;

  Timer? _capabilitiesTimeoutTimer;
  int _reRegisterCount = 0;
  bool _hasReceivedCapabilities = false;
  bool _awaitingPostReconnectCapabilities = false;

  /// Whether the most recent handshake reached a successful negotiation.
  bool get hasReceivedCapabilities => _hasReceivedCapabilities;

  /// Marks the next successful negotiation as the conclusion of an automatic
  /// reconnect cycle; the [CapabilitiesNegotiationSuccess] result will carry
  /// `wasPostReconnect == true` so the transport can fire
  /// `HubTransportAutoReconnectSucceeded`.
  void markAwaitingPostReconnectCapabilities() {
    _awaitingPostReconnectCapabilities = true;
  }

  /// Resets transient state. Call from the transport client whenever the
  /// underlying socket is closed or a fresh `connect()` starts.
  void reset() {
    _capabilitiesTimeoutTimer?.cancel();
    _capabilitiesTimeoutTimer = null;
    _reRegisterCount = 0;
    _hasReceivedCapabilities = false;
    _awaitingPostReconnectCapabilities = false;
  }

  /// Handles an `agent:register_error` event from the hub. Cancels the in-flight
  /// timeout watchdog, logs the structured error, and triggers a forced
  /// reconnect when the error is non-recoverable. Recoverable errors (e.g.
  /// `transient_failure`) are logged and left for the next periodic re-register
  /// timer to retry.
  void handleRegisterError(Map<String, dynamic> error) {
    final code = error['code']?.toString();
    final reason = error['reason']?.toString();
    final message = error['message']?.toString() ?? 'agent:register rejected by hub';

    AppLogger.warning(
      'agent:register_error code=$code reason=$reason message=$message',
    );

    _capabilitiesTimeoutTimer?.cancel();
    _capabilitiesTimeoutTimer = null;

    if (_isRecoverableRegisterError(code, reason)) {
      // Schedule another attempt via the standard timeout/re-register loop.
      _startTimeoutTimer();
      return;
    }

    _onTimeoutReconnect();
  }

  static bool _isRecoverableRegisterError(String? code, String? reason) {
    if (code == null && reason == null) return false;
    final lc = (code ?? '').toLowerCase();
    final lr = (reason ?? '').toLowerCase();
    return lc == 'transient_failure' || lr == 'transient_failure' || lc == 'rate_limited' || lr == 'rate_limited';
  }

  /// Sends the `agent:register` frame followed by the timeout watchdog.
  Future<void> sendRegisterAndStartTimeout() async {
    _reRegisterCount = 0;
    await _sendAgentRegister();
    _startTimeoutTimer();
  }

  /// Same as [sendRegisterAndStartTimeout] but invoked on the `reconnect`
  /// event so the success callback can carry the post-reconnect flag.
  Future<void> sendReRegisterAfterReconnect() async {
    _reRegisterCount = 0;
    _awaitingPostReconnectCapabilities = true;
    await _sendAgentRegister();
    _startTimeoutTimer();
  }

  /// Processes the `agent:capabilities` envelope received from the hub.
  CapabilitiesNegotiationOutcome handleEnvelope(dynamic data) {
    try {
      final payload = _decodeIncoming(data, sourceEvent: 'agent:capabilities');
      if (payload is! Map<String, dynamic>) {
        throw StateError('agent:capabilities payload must be an object');
      }
      if (_featureFlags.enableSocketSchemaValidation) {
        final validation = _contractValidator.validateAgentCapabilitiesEnvelope(payload);
        if (validation.isError()) {
          final failure = validation.exceptionOrNull()! as domain.Failure;
          throw StateError(failure.message);
        }
      }

      final agentCapabilities = _localCapabilitiesProvider();
      final serverCapabilities = payload['capabilities'] != null
          ? ProtocolCapabilities.fromJson(payload['capabilities'] as Map<String, dynamic>)
          : agentCapabilities;

      final negotiatedProtocol = _negotiator.negotiate(
        agentCapabilities: agentCapabilities,
        serverCapabilities: serverCapabilities,
      );

      _validateNegotiatedTransportContract(
        negotiatedProtocol: negotiatedProtocol,
        agentCapabilities: agentCapabilities,
        serverCapabilities: serverCapabilities,
      );

      _capabilitiesTimeoutTimer?.cancel();
      _capabilitiesTimeoutTimer = null;
      _hasReceivedCapabilities = true;

      final wasPostReconnect = _awaitingPostReconnectCapabilities;
      _awaitingPostReconnectCapabilities = false;

      return CapabilitiesNegotiationSuccess(
        negotiatedProtocol: negotiatedProtocol,
        wasPostReconnect: wasPostReconnect,
      );
    } on Object catch (error, stackTrace) {
      _awaitingPostReconnectCapabilities = false;
      return CapabilitiesNegotiationFailure(error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _sendAgentRegister() async {
    final agentCapabilities = _localCapabilitiesProvider();

    final registerData = {
      'agentId': _agentIdProvider(),
      'timestamp': DateTime.now().toIso8601String(),
      'capabilities': agentCapabilities.toJson(),
    };

    if (_featureFlags.enableSocketSchemaValidation) {
      final validation = _contractValidator.validateAgentRegister(registerData);
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()! as domain.Failure;
        AppLogger.error('Invalid agent:register payload: ${failure.message}');
        return;
      }
    }

    await _emit('agent:register', registerData);
  }

  void _startTimeoutTimer() {
    _capabilitiesTimeoutTimer?.cancel();
    _capabilitiesTimeoutTimer = Timer(
      const Duration(milliseconds: ConnectionConstants.capabilitiesTimeoutMs),
      () {
        if (_hasReceivedCapabilities) return;
        if (_reRegisterCount < ConnectionConstants.capabilitiesMaxReRegisterAttempts) {
          _reRegisterCount++;
          AppLogger.warning(
            'resilience: capabilities_timeout re_register_count=$_reRegisterCount '
            'max=${ConnectionConstants.capabilitiesMaxReRegisterAttempts}',
          );
          unawaited(_sendAgentRegister());
          _startTimeoutTimer();
        } else {
          AppLogger.warning(
            'resilience: capabilities_timeout forcing_reconnect after_max_attempts',
          );
          _reRegisterCount = 0;
          _onTimeoutReconnect();
        }
      },
    );
  }

  void _validateNegotiatedTransportContract({
    required ProtocolConfig negotiatedProtocol,
    required ProtocolCapabilities agentCapabilities,
    required ProtocolCapabilities serverCapabilities,
  }) {
    if (!agentCapabilities.supportsBinaryPayload ||
        !serverCapabilities.supportsBinaryPayload ||
        !negotiatedProtocol.usesBinaryPayload ||
        !negotiatedProtocol.usesTransportFrame) {
      throw StateError(
        'Negotiated protocol does not satisfy mandatory binary PayloadFrame transport',
      );
    }

    final localCompressionThreshold = agentCapabilities.extensions['compressionThreshold'];
    if (localCompressionThreshold is! int || localCompressionThreshold < 1) {
      throw StateError('Local compressionThreshold capability is invalid');
    }
    if (negotiatedProtocol.compressionThreshold < 1) {
      throw StateError('Negotiated compressionThreshold is invalid');
    }
    if (negotiatedProtocol.maxInflationRatio < 1) {
      throw StateError('Negotiated maxInflationRatio is invalid');
    }

    final agentRequiresSignature = agentCapabilities.extensions['signatureRequired'] as bool? ?? false;
    final serverRequiresSignature = serverCapabilities.extensions['signatureRequired'] as bool? ?? false;
    if ((agentRequiresSignature || serverRequiresSignature) && negotiatedProtocol.signatureAlgorithms.isEmpty) {
      throw StateError(
        'Negotiated protocol requires signature but no shared algorithm was found',
      );
    }
    if (negotiatedProtocol.signatureRequired && _payloadSigner == null) {
      throw StateError(
        'Negotiated protocol requires transport signing but no signer is configured',
      );
    }
    if (negotiatedProtocol.signatureRequired &&
        !negotiatedProtocol.signatureAlgorithms.contains(PayloadSigner.supportedAlgorithm)) {
      throw StateError(
        'Negotiated protocol requires unsupported signature algorithm',
      );
    }
  }
}
