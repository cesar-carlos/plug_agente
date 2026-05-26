import 'package:plug_agente/domain/actions/action_policies.dart'
    show AgentActionEnvironmentPolicy, AgentActionRemotePolicy;
import 'package:plug_agente/domain/actions/actions.dart' show AgentActionEnvironmentPolicy, AgentActionRemotePolicy;
import 'package:plug_agente/domain/domain.dart' show AgentActionEnvironmentPolicy, AgentActionRemotePolicy;

/// Stable `failure.context['reason']` for agent action feature, maintenance, remote, and lifecycle gates.
abstract final class AgentActionGateConstants {
  static const String actionNotActiveReason = 'action_not_active';

  static const String featureDisabledReason = 'feature_disabled';

  static const String maintenanceModeReason = 'maintenance_mode';

  static const String remoteFeatureDisabledReason = 'remote_feature_disabled';

  static const String remoteAdHocDisabledReason = 'remote_ad_hoc_disabled';

  static const String elevatedDisabledReason = 'elevated_disabled';

  static const String elevatedNotConfiguredReason = 'elevated_not_configured';

  static const String elevatedRunnerDegradedReason = 'elevated_runner_degraded';

  static const String elevatedRequestProtectionFailedReason = 'elevated_request_protection_failed';

  static const String elevatedSubmitFailedReason = 'elevated_submit_failed';

  static const String unsupportedForElevatedRunnerReason = 'unsupported_for_elevated_runner';

  static const String remoteActionNotApprovedReason = 'remote_action_not_approved';

  /// Remote approval stored [AgentActionRemotePolicy.riskFingerprint] no longer matches current risk (e.g. secret rotation).
  static const String remoteRiskFingerprintStaleReason = 'remote_risk_fingerprint_stale';

  static const String remoteContextNotSupportedReason = 'remote_context_not_supported';

  static const String environmentProfileDeniedReason = 'environment_profile_denied';

  static const String secretUnavailableReason = 'action_secret_unavailable';

  /// Optional operational profile for [AgentActionEnvironmentPolicy] (`dev`, `homolog`, `prod`, etc.).
  static const String operationalProfileEnvironmentKey = 'AGENT_OPERATIONAL_PROFILE';

  static const String prodOperationalProfileName = 'prod';
}
