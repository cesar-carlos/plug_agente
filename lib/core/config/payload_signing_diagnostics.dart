import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';

enum PayloadSigningHealthStatus {
  ok,
  warning,
  error,
}

class PayloadSigningHealthIssue {
  const PayloadSigningHealthIssue({
    required this.code,
    required this.message,
    required this.status,
  });

  final String code;
  final String message;
  final PayloadSigningHealthStatus status;

  Map<String, String> toJson() {
    return <String, String>{
      'code': code,
      'message': message,
      'status': status.name,
    };
  }
}

class PayloadSigningDiagnostics {
  PayloadSigningDiagnostics({
    required this.status,
    required this.issues,
    required this.outgoingSigningEnabled,
    required this.incomingSignatureRequired,
    required this.signerConfigured,
    required this.activeKeyId,
    required this.keyCount,
    required this.rotationReady,
    required this.keySource,
    required this.secureStorageAvailable,
  });

  factory PayloadSigningDiagnostics.evaluate({
    required FeatureFlags featureFlags,
    required PayloadSigningConfig config,
  }) {
    final issues = <PayloadSigningHealthIssue>[];
    final signerConfigured = config.hasConfiguredSigner;
    final activeKeyId = config.activeKeyId;

    if (featureFlags.enablePayloadSigning && !signerConfigured) {
      issues.add(
        const PayloadSigningHealthIssue(
          code: 'payload_signing_enabled_without_key',
          message: 'Outgoing PayloadFrame signing is enabled, but no active signing key is configured.',
          status: PayloadSigningHealthStatus.error,
        ),
      );
    }
    if (featureFlags.requireIncomingPayloadSignatures && !signerConfigured) {
      issues.add(
        const PayloadSigningHealthIssue(
          code: 'incoming_signatures_required_without_key',
          message: 'Incoming PayloadFrame signatures are required, but the agent cannot verify frames without a key.',
          status: PayloadSigningHealthStatus.error,
        ),
      );
    }
    if (config.keys.isNotEmpty && activeKeyId == null) {
      issues.add(
        const PayloadSigningHealthIssue(
          code: 'payload_signing_active_key_missing',
          message: 'Signing keys exist, but no active key id is selected.',
          status: PayloadSigningHealthStatus.error,
        ),
      );
    }
    if (activeKeyId != null && !config.keys.containsKey(activeKeyId)) {
      issues.add(
        const PayloadSigningHealthIssue(
          code: 'payload_signing_active_key_not_found',
          message: 'The selected active signing key id is not present in the configured key set.',
          status: PayloadSigningHealthStatus.error,
        ),
      );
    }
    if (!config.secureStorageAvailable && config.keys.isNotEmpty) {
      issues.add(
        const PayloadSigningHealthIssue(
          code: 'payload_signing_secure_storage_unavailable',
          message: 'Payload signing keys are configured, but secure storage is unavailable on this runtime.',
          status: PayloadSigningHealthStatus.warning,
        ),
      );
    }
    if (config.keyCount == 1 && signerConfigured) {
      issues.add(
        const PayloadSigningHealthIssue(
          code: 'payload_signing_rotation_single_key',
          message: 'Only one signing key is configured. Add a second key before rotating key ids in production.',
          status: PayloadSigningHealthStatus.warning,
        ),
      );
    }
    for (final warning in config.warnings) {
      issues.add(
        PayloadSigningHealthIssue(
          code: warning,
          message: 'Payload signing configuration warning: $warning.',
          status: PayloadSigningHealthStatus.warning,
        ),
      );
    }

    return PayloadSigningDiagnostics(
      status: _resolveStatus(issues),
      issues: List<PayloadSigningHealthIssue>.unmodifiable(issues),
      outgoingSigningEnabled: featureFlags.enablePayloadSigning,
      incomingSignatureRequired: featureFlags.requireIncomingPayloadSignatures,
      signerConfigured: signerConfigured,
      activeKeyId: activeKeyId,
      keyCount: config.keyCount,
      rotationReady: signerConfigured && config.keyCount > 1,
      keySource: config.sourceName,
      secureStorageAvailable: config.secureStorageAvailable,
    );
  }

  final PayloadSigningHealthStatus status;
  final List<PayloadSigningHealthIssue> issues;
  final bool outgoingSigningEnabled;
  final bool incomingSignatureRequired;
  final bool signerConfigured;
  final String? activeKeyId;
  final int keyCount;
  final bool rotationReady;
  final String keySource;
  final bool secureStorageAvailable;

  bool get hasBlockingIssue => status == PayloadSigningHealthStatus.error;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': status.name,
      'outgoing_signing_enabled': outgoingSigningEnabled,
      'incoming_signature_required': incomingSignatureRequired,
      'signer_configured': signerConfigured,
      'active_key_id': activeKeyId,
      'key_count': keyCount,
      'rotation_ready': rotationReady,
      'key_source': keySource,
      'secure_storage_available': secureStorageAvailable,
      if (issues.isNotEmpty) 'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }

  static PayloadSigningHealthStatus _resolveStatus(List<PayloadSigningHealthIssue> issues) {
    if (issues.any((issue) => issue.status == PayloadSigningHealthStatus.error)) {
      return PayloadSigningHealthStatus.error;
    }
    if (issues.any((issue) => issue.status == PayloadSigningHealthStatus.warning)) {
      return PayloadSigningHealthStatus.warning;
    }
    return PayloadSigningHealthStatus.ok;
  }
}
