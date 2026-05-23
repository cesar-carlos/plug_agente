import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

extension HubRecoveryUiHintL10n on HubRecoveryUiHint {
  String connectionStatusLabel(AppLocalizations l10n) {
    return switch (this) {
      HubRecoveryUiHint.signingIn => l10n.connectionStatusHubReconnectingSigningIn,
      HubRecoveryUiHint.connectingSocket => l10n.connectionStatusHubReconnectingSocket,
      HubRecoveryUiHint.awaitingHubReachability => l10n.connectionStatusHubReconnectingWaitingHub,
      HubRecoveryUiHint.negotiationTimedOut => l10n.connectionStatusHubReconnectingNegotiationTimedOut,
      HubRecoveryUiHint.none => l10n.connectionStatusHubReconnecting,
    };
  }
}
