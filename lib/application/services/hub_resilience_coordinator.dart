import 'dart:async';
import 'dart:math';

import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/async_operation_gate.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:result_dart/result_dart.dart';

enum TokenRefreshResultKind {
  refreshed,
  skippedByCooldown,
  transientFailure,
  terminalFailure,
}

class TokenRefreshResult {
  const TokenRefreshResult._({
    required this.kind,
    this.token,
  });

  const TokenRefreshResult.refreshed(String token) : this._(kind: TokenRefreshResultKind.refreshed, token: token);

  const TokenRefreshResult.skippedByCooldown() : this._(kind: TokenRefreshResultKind.skippedByCooldown);

  const TokenRefreshResult.transientFailure() : this._(kind: TokenRefreshResultKind.transientFailure);

  const TokenRefreshResult.terminalFailure() : this._(kind: TokenRefreshResultKind.terminalFailure);

  final TokenRefreshResultKind kind;
  final String? token;
}

enum HardReloginOutcome {
  success,
  skippedCooldown,
  authBridgeUnavailable,
  transientFailure,
  failed,
}

class HardReloginResult {
  const HardReloginResult({
    required this.outcome,
    this.token,
    this.failureMessage,
  });

  final HardReloginOutcome outcome;
  final String? token;
  final String? failureMessage;
}

/// Runtime callbacks supplied by the presentation layer for hub resilience orchestration.
class HubResilienceEnvironment {
  const HubResilienceEnvironment({
    required this.isDisconnectRequested,
    required this.isBurstRecoveryInFlight,
    required this.hasPersistentRetryTimer,
    required this.persistentRetryInFlight,
    required this.isNegotiating,
    required this.resolveConnectionContext,
    required this.lastAgentId,
    required this.syncTransportResilienceLogContext,
    required this.handleReconnectionNeeded,
    required this.onNegotiatingWatchdogTimeoutWithoutContext,
    required this.onNegotiatingWatchdogTimeoutWithContext,
  });

  final bool Function() isDisconnectRequested;

  /// True only while app burst recovery is running — not while waiting for Socket.IO L0.
  final bool Function() isBurstRecoveryInFlight;
  final bool Function() hasPersistentRetryTimer;
  final bool Function() persistentRetryInFlight;
  final bool Function() isNegotiating;
  final HubConnectionContext? Function() resolveConnectionContext;
  final String? Function() lastAgentId;
  final void Function(String? recoveryId) syncTransportResilienceLogContext;
  final Future<void> Function() handleReconnectionNeeded;
  final void Function({required int timeoutMs}) onNegotiatingWatchdogTimeoutWithoutContext;
  final void Function() onNegotiatingWatchdogTimeoutWithContext;
}

/// Owns hub connect serialization, recovery coalescing, negotiation watchdog, and recovery routing.
class HubResilienceCoordinator {
  HubResilienceCoordinator({
    required HubResilienceEnvironment environment,
    IConnectionContextSource? connectionContextSource,
    IHubRecoveryAuthBridge? recoveryAuthBridge,
    HubAccessTokenRefreshGate? tokenRefreshGate,
    Duration tokenRefreshMinInterval = ConnectionConstants.hubTokenRefreshMinInterval,
    Duration? capabilitiesNegotiationWatchdogOverride,
    Random? random,
    AsyncOperationGate? hubConnectGate,
    ExclusiveRecoveryGate? recoveryGate,
  }) : _environment = environment,
       _connectionContextSource = connectionContextSource,
       _recoveryAuthBridge = recoveryAuthBridge,
       _tokenRefreshGate = tokenRefreshGate ?? HubAccessTokenRefreshGate(minInterval: tokenRefreshMinInterval),
       _capabilitiesNegotiationWatchdogOverride = capabilitiesNegotiationWatchdogOverride,
       _random = random,
       _hubConnectGate = hubConnectGate ?? AsyncOperationGate(),
       _recoveryGate = recoveryGate ?? ExclusiveRecoveryGate();

  final HubResilienceEnvironment _environment;
  final IConnectionContextSource? _connectionContextSource;
  IHubRecoveryAuthBridge? _recoveryAuthBridge;
  final HubAccessTokenRefreshGate _tokenRefreshGate;
  final Duration? _capabilitiesNegotiationWatchdogOverride;
  final Random? _random;
  final AsyncOperationGate _hubConnectGate;
  final ExclusiveRecoveryGate _recoveryGate;

  Timer? _negotiatingWatchdog;
  String? _resilienceRecoveryId;
  DateTime? _lastHardReloginEndedAt;

  String? get recoveryId => _resilienceRecoveryId;

  void attachRecoveryAuthBridge(IHubRecoveryAuthBridge? bridge) {
    _recoveryAuthBridge = bridge;
  }

  Duration get effectiveNegotiatingWatchdog =>
      _capabilitiesNegotiationWatchdogOverride ??
      Duration(milliseconds: ConnectionConstants.capabilitiesNegotiationWatchdogMs);

  String resilienceLogPrefix() {
    final id = _resilienceRecoveryId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return 'recovery_id=$id ';
  }

  void invalidateHubConnectEpoch() {
    _hubConnectGate.invalidateEpoch();
  }

  Future<T> runSerializedHubConnect<T>(
    Future<T> Function() action, {
    T? staleResult,
  }) {
    return _hubConnectGate.runSerialized(
      action,
      staleResult: staleResult,
      shouldAbort: _environment.isDisconnectRequested,
    );
  }

  void beginResilienceRecovery() {
    if (_resilienceRecoveryId != null && _resilienceRecoveryId!.isNotEmpty) {
      _syncTransportResilienceLogContext();
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final entropy = _random?.nextInt(0x100000) ?? 0;
    _resilienceRecoveryId = 'rec-${stamp}_${entropy.toRadixString(16)}';
    _syncTransportResilienceLogContext();
  }

  void clearResilienceRecovery() {
    _resilienceRecoveryId = null;
    _syncTransportResilienceLogContext();
  }

  void armNegotiatingWatchdog() {
    cancelNegotiatingWatchdog();
    _negotiatingWatchdog = Timer(effectiveNegotiatingWatchdog, _onNegotiatingWatchdogFired);
  }

  void cancelNegotiatingWatchdog() {
    _negotiatingWatchdog?.cancel();
    _negotiatingWatchdog = null;
  }

  Future<void> scheduleExclusiveRecovery() {
    return _recoveryGate.schedule(
      handler: _environment.handleReconnectionNeeded,
      shouldAbort: _environment.isDisconnectRequested,
      shouldSkipAfterLock: () =>
          _environment.isBurstRecoveryInFlight() ||
          _environment.hasPersistentRetryTimer() ||
          _environment.persistentRetryInFlight(),
      onCoalesced: () {
        AppLogger.debug(
          'resilience: ${resilienceLogPrefix()}reconnect event=recovery_coalesced '
          'reason=handler_already_scheduled',
        );
      },
      onSkippedAfterLock: () {
        AppLogger.debug(
          'resilience: ${resilienceLogPrefix()}reconnect event=recovery_skipped '
          'reason=already_recovering burst_in_flight=${_environment.isBurstRecoveryInFlight()} '
          'persistent_timer=${_environment.hasPersistentRetryTimer()}',
        );
      },
    );
  }

  void kickHubTransportRecovery({required String trigger}) {
    if (_environment.isDisconnectRequested()) {
      return;
    }
    if (_environment.isBurstRecoveryInFlight()) {
      AppLogger.debug(
        'resilience: ${resilienceLogPrefix()}hub_transport event=recovery_skipped '
        'trigger=$trigger reason=burst_in_flight',
      );
      return;
    }
    if (_environment.hasPersistentRetryTimer()) {
      AppLogger.debug(
        'resilience: ${resilienceLogPrefix()}hub_transport event=recovery_skipped '
        'trigger=$trigger reason=persistent_retry_active',
      );
      return;
    }
    if (_environment.persistentRetryInFlight()) {
      AppLogger.debug(
        'resilience: ${resilienceLogPrefix()}hub_transport event=recovery_skipped '
        'trigger=$trigger reason=persistent_tick_in_flight',
      );
      return;
    }
    unawaited(scheduleExclusiveRecovery());
  }

  void dispose() {
    cancelNegotiatingWatchdog();
  }

  HubConnectionContext? resolveConnectionContext() {
    return _connectionContextSource?.resolveConnectionContext() ?? _environment.resolveConnectionContext();
  }

  String? resolveAuthTokenForReconnect() {
    return _connectionContextSource?.resolveAuthTokenForReconnect();
  }

  String resolveActiveConfigId(String? candidateConfigId) {
    return _connectionContextSource?.resolveActiveConfigId(candidateConfigId) ??
        candidateConfigId?.trim() ??
        'unknown-config';
  }

  bool isHardReloginCooldownActive(Duration cooldown) {
    if (cooldown <= Duration.zero) {
      return false;
    }
    final last = _lastHardReloginEndedAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) < cooldown;
  }

  Future<TokenRefreshResult> tryRefreshToken(HubConnectionContext context) async {
    final bridge = _recoveryAuthBridge;
    if (bridge == null) {
      return const TokenRefreshResult.terminalFailure();
    }

    final refreshResult = await _tokenRefreshGate.runExclusive<Result<AuthToken>>(
      () => bridge.refreshSession(
        context.serverUrl,
        configId: context.configId,
        currentToken: bridge.currentTokenForConfig(context.configId),
      ),
      logContext: 'resilience: ${resilienceLogPrefix()}token_refresh',
    );

    if (refreshResult == null) {
      return const TokenRefreshResult.skippedByCooldown();
    }

    return refreshResult.fold(
      (token) {
        bridge.restoreToken(token, configId: context.configId, silent: true);
        final normalizedToken = token.token.trim();
        return TokenRefreshResult.refreshed(normalizedToken);
      },
      (Object failure) {
        if (failure is domain_errors.Failure && failure.isTransient) {
          AppLogger.warning(
            'resilience: ${resilienceLogPrefix()}token_refresh event=transient_failure '
            'display=${failure.toDisplayMessage()} '
            'technical=${failure.toTechnicalMessage()}',
          );
          return const TokenRefreshResult.transientFailure();
        }
        bridge.setRecoveryError(failure.toDisplayMessage());
        return const TokenRefreshResult.terminalFailure();
      },
    );
  }

  Future<HardReloginResult> executeHardRelogin(
    HubConnectionContext context, {
    required String logSummary,
    required Duration hardReloginCooldown,
    bool ignoreCooldown = false,
  }) async {
    if (!ignoreCooldown && isHardReloginCooldownActive(hardReloginCooldown)) {
      final last = _lastHardReloginEndedAt;
      final remainingMs = last == null ? 0 : (hardReloginCooldown - DateTime.now().difference(last)).inMilliseconds;
      AppLogger.info(
        'resilience: ${resilienceLogPrefix()}hard_relogin event=skipped_cooldown '
        'remaining_ms=${remainingMs.clamp(0, 86400000)} '
        'agent_id=${context.agentId}',
      );
      return const HardReloginResult(outcome: HardReloginOutcome.skippedCooldown);
    }

    final bridge = _recoveryAuthBridge;
    if (bridge == null) {
      return const HardReloginResult(outcome: HardReloginOutcome.authBridgeUnavailable);
    }

    try {
      AppLogger.warning(
        'resilience: ${resilienceLogPrefix()}hard_relogin event=started $logSummary '
        'agent_id=${context.agentId}',
      );
      await bridge.logout(configId: context.configId);

      final reloginResult = await bridge.loginWithStoredCredentials(
        context.serverUrl,
        context.agentId,
        configId: context.configId,
      );
      return reloginResult.fold(
        (token) {
          bridge.restoreToken(token, configId: context.configId, silent: true);
          return HardReloginResult(
            outcome: HardReloginOutcome.success,
            token: token.token.trim(),
          );
        },
        (Object failure) {
          final isTransient = failure is domain_errors.Failure && failure.isTransient;
          if (isTransient) {
            AppLogger.warning(
              'resilience: ${resilienceLogPrefix()}hard_relogin event=transient_failure '
              'display=${failure.toDisplayMessage()} '
              'technical=${failure.toTechnicalMessage()}',
            );
            return const HardReloginResult(outcome: HardReloginOutcome.transientFailure);
          }
          unawaited(bridge.clearStoredSession(context.configId));
          bridge.setRecoveryError(failure.toDisplayMessage());
          return HardReloginResult(
            outcome: HardReloginOutcome.failed,
            failureMessage: failure.toDisplayMessage(),
          );
        },
      );
    } finally {
      _lastHardReloginEndedAt = DateTime.now();
    }
  }

  void resetAuthRecoveryState() {
    _tokenRefreshGate.reset();
    _lastHardReloginEndedAt = null;
  }

  void _syncTransportResilienceLogContext() {
    _environment.syncTransportResilienceLogContext(_resilienceRecoveryId);
  }

  void _onNegotiatingWatchdogFired() {
    if (_environment.isDisconnectRequested() || !_environment.isNegotiating()) {
      return;
    }
    final context = resolveConnectionContext();
    final timeoutMs = effectiveNegotiatingWatchdog.inMilliseconds;
    AppLogger.warning(
      'resilience: ${resilienceLogPrefix()}negotiation_watchdog event=timeout '
      'timeout_ms=$timeoutMs agent_id=${context?.agentId ?? _environment.lastAgentId() ?? "?"}',
    );
    if (context == null) {
      cancelNegotiatingWatchdog();
      _environment.onNegotiatingWatchdogTimeoutWithoutContext(timeoutMs: timeoutMs);
      return;
    }
    beginResilienceRecovery();
    _environment.onNegotiatingWatchdogTimeoutWithContext();
    kickHubTransportRecovery(trigger: 'negotiating_watchdog');
  }
}
