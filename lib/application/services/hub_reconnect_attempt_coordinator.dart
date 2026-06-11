import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

/// Serialized hub transport reconnect attempts during recovery bursts.
final class HubReconnectAttemptCoordinator {
  HubReconnectAttemptCoordinator({
    required HubReconnectAttemptRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubReconnectAttemptRuntimeDependencies _deps;

  Future<bool> attemptReconnect(
    String serverUrl,
    String agentId, {
    String? authToken,
    bool recordErrorMessage = true,
  }) async {
    return _deps.resilienceCoordinator.runSerializedHubConnect<bool>(
      () async {
        if (_deps.isDisconnectRequested()) {
          return false;
        }
        if (_deps.isReconnectingUiState()) {
          _deps.setHubRecoveryUiHint(HubRecoveryUiHint.connectingSocket);
        }
        final result = await _deps.connectToHubUseCase(
          serverUrl,
          agentId,
          authToken: authToken,
        );

        return result.fold(
          (_) {
            _deps.cancelPersistentRetryTimer();
            _deps.onTransportConnectSuccessDuringRecovery();
            _deps.onTransportReconnectSuccess(
              serverUrl: serverUrl,
              agentId: agentId,
              authToken: authToken,
            );
            AppLogger.info(
              'resilience: ${_deps.resilienceLogPrefix()}hub_connect event=transport_succeeded agent_id=$agentId',
            );
            _deps.clearHubRecoveryUiHint();
            return true;
          },
          (Object failure) {
            _deps.onTransportConnectFailureDuringRecovery();
            _deps.onTransportReconnectFailure(
              message: recordErrorMessage ? failure.toDisplayMessage() : '',
            );
            if (recordErrorMessage) {
              AppLogger.warning(
                'Reconnection attempt failed: ${failure.toDisplayMessage()}',
                failure.toTechnicalMessage(),
              );
            } else {
              final count = _deps.bumpReconnectQuietFailureLogCount();
              const stride = ConnectionConstants.hubReconnectFailureLogThrottleStride;
              if (count == 1 || count % stride == 0) {
                AppLogger.warning(
                  'resilience: ${_deps.resilienceLogPrefix()}reconnect event=attempt_failed_throttled '
                  'count=$count stride=$stride '
                  'display=${failure.toDisplayMessage()}',
                  failure.toTechnicalMessage(),
                );
              }
            }
            _deps.clearHubRecoveryUiHint();
            return false;
          },
        );
      },
      staleResult: false,
    );
  }
}

final class HubReconnectAttemptRuntimeDependencies {
  HubReconnectAttemptRuntimeDependencies({
    required this.connectToHubUseCase,
    required this.resilienceCoordinator,
    required this.onTransportConnectSuccessDuringRecovery,
    required this.onTransportConnectFailureDuringRecovery,
    required this.resilienceLogPrefix,
    required this.isDisconnectRequested,
    required this.isReconnectingUiState,
    required this.cancelPersistentRetryTimer,
    required this.onTransportReconnectSuccess,
    required this.onTransportReconnectFailure,
    required this.resetReconnectQuietFailureLogCount,
    required this.bumpReconnectQuietFailureLogCount,
    required this.setHubRecoveryUiHint,
    required this.clearHubRecoveryUiHint,
  });

  final ConnectToHub connectToHubUseCase;
  final HubResilienceCoordinator resilienceCoordinator;
  final void Function() onTransportConnectSuccessDuringRecovery;
  final void Function() onTransportConnectFailureDuringRecovery;
  final String Function() resilienceLogPrefix;
  final bool Function() isDisconnectRequested;
  final bool Function() isReconnectingUiState;
  final void Function() cancelPersistentRetryTimer;
  final void Function({
    required String serverUrl,
    required String agentId,
    String? authToken,
  })
  onTransportReconnectSuccess;
  final void Function({required String message}) onTransportReconnectFailure;
  final void Function() resetReconnectQuietFailureLogCount;
  final int Function() bumpReconnectQuietFailureLogCount;
  final void Function(HubRecoveryUiHint hint) setHubRecoveryUiHint;
  final void Function() clearHubRecoveryUiHint;
}
