import 'dart:async';
import 'dart:math';

import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/transport_reconnect_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/reconnect_delay_calculator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

/// Burst/persistent hub recovery policy and loops; UI and connection tracking
/// mutations are delegated via [HubRecoveryRuntimeDependencies].
final class HubRecoveryOrchestrator {
  HubRecoveryOrchestrator({
    required this.initialReconnectDelay,
    required this.maxReconnectDelay,
    required HubRecoveryRuntimeDependencies runtime,
    this.random,
  }) : _deps = runtime;

  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;
  final Random? random;
  final HubRecoveryRuntimeDependencies _deps;

  int consecutiveReconnectFailures = 0;
  bool hardReloginAttemptedInCycle = false;
  int persistentRetryTickCount = 0;
  int persistentFailureCount = 0;

  Duration reconnectDelayForAttempt(int attempt) {
    return computeReconnectDelay(
      attempt: attempt,
      initialDelay: initialReconnectDelay,
      maxDelay: maxReconnectDelay,
      random: random,
    );
  }

  void resetForDisconnect() {
    hardReloginAttemptedInCycle = false;
    consecutiveReconnectFailures = 0;
  }

  void resetForUserConnect() {
    persistentFailureCount = 0;
    consecutiveReconnectFailures = 0;
    hardReloginAttemptedInCycle = false;
  }

  void resetForStartupPersistentRecovery() {
    persistentFailureCount = 0;
    persistentRetryTickCount = 0;
    consecutiveReconnectFailures = 0;
    hardReloginAttemptedInCycle = false;
  }

  void resetPersistentRetryCounters() {
    persistentRetryTickCount = 0;
    persistentFailureCount = 0;
  }

  void resetHardReloginCycle() {
    hardReloginAttemptedInCycle = false;
  }

  void markHardReloginAttempted() {
    hardReloginAttemptedInCycle = true;
  }

  void noteTransportConnectSuccessDuringRecovery() {
    persistentFailureCount = 0;
    consecutiveReconnectFailures = 0;
  }

  void noteTransportConnectFailureDuringRecovery() {
    consecutiveReconnectFailures++;
  }

  void resetConsecutiveFailuresAfterHardReloginSuccess() {
    consecutiveReconnectFailures = 0;
  }

  void bumpPersistentFailure() {
    persistentFailureCount++;
  }

  void bumpPersistentTick() {
    persistentRetryTickCount++;
  }

  bool shouldEscalateToHardRelogin({
    required bool recoveryEnabled,
    required int failureThreshold,
  }) {
    if (!recoveryEnabled || hardReloginAttemptedInCycle) {
      return false;
    }
    return consecutiveReconnectFailures >= failureThreshold;
  }

  Future<bool> isHubReachableForReconnect(
    String serverUrl, {
    required String stage,
  }) async {
    final check = _deps.checkHubAvailability;
    if (check == null) {
      return true;
    }
    final sw = Stopwatch()..start();
    final isReachable = await check(serverUrl);
    sw.stop();
    final elapsedMs = sw.elapsedMilliseconds;
    if (elapsedMs >= ConnectionConstants.hubAvailabilityProbeSlowLogThresholdMs) {
      AppLogger.info(
        'resilience: ${_deps.resilienceLogPrefix()}hub_probe_slow elapsed_ms=$elapsedMs stage=$stage server=$serverUrl '
        'reachable=$isReachable',
      );
    }
    if (!isReachable) {
      AppLogger.info(
        'resilience: ${_deps.resilienceLogPrefix()}hub_probe_offline stage=$stage server=$serverUrl elapsed_ms=$elapsedMs',
      );
    }
    return isReachable;
  }

  Future<TokenRefreshResult> tryRefreshToken(HubConnectionContext context) {
    return _deps.tryRefreshToken(context);
  }

  Future<bool> runBurstRecovery(
    HubConnectionContext context, {
    required bool proactiveHardReloginBeforeSocket,
    required bool effectiveHardReloginRecoveryEnabled,
    required bool hasAuthBridge,
    required int maxReconnectAttempts,
    required int tokenRefreshIntervalAttempts,
    required bool recoveryEnabled,
    required int hardReloginFailureThreshold,
  }) async {
    final prefix = _deps.resilienceLogPrefix();
    AppLogger.info(
      'resilience: ${prefix}burst_recovery event=started max_attempts=$maxReconnectAttempts '
      'agent_id=${context.agentId}',
    );
    var didProactiveHardRelogin = false;
    if (proactiveHardReloginBeforeSocket && effectiveHardReloginRecoveryEnabled && hasAuthBridge) {
      AppLogger.info(
        'resilience: ${prefix}burst_recovery event=pre_socket_full_relogin '
        'agent_id=${context.agentId}',
      );
      await _deps.disconnectTransportForRecovery();
      markHardReloginAttempted();
      await _deps.executeHardRelogin(
        context,
        logSummary: 'trigger=before_socket_recovery',
        ignoreCooldown: true,
      );
      if (_deps.isDisconnectRequested()) {
        return false;
      }
      if (_deps.isStatusError()) {
        return false;
      }
      didProactiveHardRelogin = true;
    }

    var authToken = _deps.contextSource.resolveAuthTokenForReconnect();
    if (!didProactiveHardRelogin) {
      final refreshResult = await tryRefreshToken(context);
      if (refreshResult.kind == TokenRefreshResultKind.refreshed) {
        authToken = refreshResult.token;
      }
    }
    for (var attempt = 1; attempt <= maxReconnectAttempts && !_deps.isDisconnectRequested(); attempt++) {
      final delay = reconnectDelayForAttempt(attempt);
      if (delay > Duration.zero) {
        AppLogger.info(
          'resilience: ${prefix}reconnect_delay_ms attempt=$attempt '
          'delay_ms=${delay.inMilliseconds} agent_id=${context.agentId}',
        );
        await Future<void>.delayed(delay);
      }

      AppLogger.info(
        'resilience: ${prefix}connect_attempt attempt=$attempt agent_id=${context.agentId}',
      );
      final hubReachable = await isHubReachableForReconnect(
        context.serverUrl,
        stage: 'burst',
      );
      if (!hubReachable) {
        AppLogger.info(
          'resilience: ${prefix}hub_unreachable_skip_connect attempt=$attempt agent_id=${context.agentId}',
        );
        _deps.uiSink.setHubRecoveryUiHint(HubRecoveryUiHint.awaitingHubReachability);
        continue;
      }
      final connected = await _deps.attemptReconnect(
        context.serverUrl,
        context.agentId,
        authToken: authToken,
      );
      if (connected) {
        AppLogger.info('Connection recovered on attempt $attempt');
        return true;
      }

      if (shouldEscalateToHardRelogin(
        recoveryEnabled: recoveryEnabled,
        failureThreshold: hardReloginFailureThreshold,
      )) {
        markHardReloginAttempted();
        final hardReloginToken = await _deps.executeHardRelogin(
          context,
          logSummary: 'trigger=consecutive_failures failures=$consecutiveReconnectFailures',
          ignoreCooldown: true,
        );
        if (hardReloginToken == null) {
          if (_deps.isStatusError()) {
            return false;
          }
        } else {
          authToken = hardReloginToken;
          final hubReachableAfterRelogin = await isHubReachableForReconnect(
            context.serverUrl,
            stage: 'hard_relogin',
          );
          if (hubReachableAfterRelogin) {
            final connectedAfterRelogin = await _deps.attemptReconnect(
              context.serverUrl,
              context.agentId,
              authToken: authToken,
            );
            if (connectedAfterRelogin) {
              AppLogger.info('Connection recovered after hard relogin');
              return true;
            }
          }
        }
      }

      if (attempt % tokenRefreshIntervalAttempts == 0) {
        final refreshResult = await tryRefreshToken(context);
        if (refreshResult.kind == TokenRefreshResultKind.refreshed && refreshResult.token != null) {
          authToken = refreshResult.token;
        }
      }
    }

    AppLogger.warning(
      'resilience: ${prefix}burst_recovery event=exhausted max_attempts=$maxReconnectAttempts '
      'agent_id=${context.agentId}',
    );
    return false;
  }

  Future<void> runPersistentTick({
    required int tokenRefreshIntervalAttempts,
    required bool recoveryEnabled,
    required int hardReloginFailureThreshold,
  }) async {
    final prefix = _deps.resilienceLogPrefix();
    resetHardReloginCycle();
    if (_deps.isDisconnectRequested()) {
      _deps.cancelPersistentRetryTimer();
      return;
    }
    final context = _deps.contextSource.resolveConnectionContext();
    if (context == null) {
      AppLogger.warning(
        'resilience: ${prefix}persistent_retry event=context_missing '
        'reason=missing_server_url_or_agent_id',
      );
      _deps.resilienceCoordinator.clearResilienceRecovery();
      _deps.cancelPersistentRetryTimer();
      return;
    }
    bumpPersistentTick();
    AppLogger.info(
      'resilience: ${prefix}hub_persistent_retry_tick tick=$persistentRetryTickCount '
      'agent_id=${context.agentId}',
    );
    if (persistentRetryTickCount % tokenRefreshIntervalAttempts == 0) {
      await tryRefreshToken(context);
    }
    final hubReachable = await isHubReachableForReconnect(
      context.serverUrl,
      stage: 'persistent',
    );
    if (!hubReachable) {
      AppLogger.info(
        'resilience: ${prefix}hub_unreachable_skip_connect tick=$persistentRetryTickCount agent_id=${context.agentId}',
      );
      _deps.uiSink.setHubRecoveryUiHint(HubRecoveryUiHint.awaitingHubReachability);
      _deps.bumpPersistentReconnectFailure(
        context,
        reason: TransportReconnectConstants.hubUnreachableReason,
      );
      return;
    }
    final authToken = _deps.contextSource.resolveAuthTokenForReconnect();
    final ok = await _deps.attemptReconnect(
      context.serverUrl,
      context.agentId,
      authToken: authToken,
      recordErrorMessage: false,
    );
    if (ok || _deps.isDisconnectRequested()) {
      if (ok) {
        AppLogger.info(
          'resilience: ${prefix}persistent_retry event=hub_reconnect_succeeded '
          'tick=$persistentRetryTickCount agent_id=${context.agentId}',
        );
      }
      return;
    }
    if (shouldEscalateToHardRelogin(
      recoveryEnabled: recoveryEnabled,
      failureThreshold: hardReloginFailureThreshold,
    )) {
      markHardReloginAttempted();
      final hardReloginToken = await _deps.executeHardRelogin(
        context,
        logSummary: 'trigger=consecutive_failures failures=$consecutiveReconnectFailures',
        ignoreCooldown: false,
      );
      if (hardReloginToken == null) {
        if (_deps.isStatusError()) {
          return;
        }
      } else {
        final connectedAfterRelogin = await _deps.attemptReconnect(
          context.serverUrl,
          context.agentId,
          authToken: hardReloginToken,
          recordErrorMessage: false,
        );
        if (connectedAfterRelogin) {
          return;
        }
      }
    }
    _deps.bumpPersistentReconnectFailure(
      context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
    );
  }
}
