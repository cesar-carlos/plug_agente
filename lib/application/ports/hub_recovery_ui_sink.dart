import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

/// Presentation hook for hub recovery UI hints (no Flutter types).
abstract interface class HubRecoveryUiSink {
  void setHubRecoveryUiHint(HubRecoveryUiHint hint);

  void clearHubRecoveryUiHint();
}
