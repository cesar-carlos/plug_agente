import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/config/payload_signing_diagnostics.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

typedef TransportDiagnosticLogCallback = void Function(
  String level,
  String event,
  Map<String, dynamic> diagnostic,
);

/// Publishes structured payload-signing diagnostics for transport lifecycle stages.
class TransportPayloadSigningDiagnosticPublisher {
  TransportPayloadSigningDiagnosticPublisher({
    required FeatureFlags featureFlags,
    required PayloadSigningConfig payloadSigningConfig,
    required PayloadSigner? payloadSigner,
    required LogRateLimiter diagnosticLogLimiter,
    required TransportDiagnosticLogCallback logMessage,
  }) : _featureFlags = featureFlags,
       _payloadSigningConfig = payloadSigningConfig,
       _payloadSigner = payloadSigner,
       _diagnosticLogLimiter = diagnosticLogLimiter,
       _logMessage = logMessage;

  final FeatureFlags _featureFlags;
  final PayloadSigningConfig _payloadSigningConfig;
  final PayloadSigner? _payloadSigner;
  final LogRateLimiter _diagnosticLogLimiter;
  final TransportDiagnosticLogCallback _logMessage;

  void publish({
    required String stage,
    required bool hasReceivedCapabilities,
    required ProtocolConfig currentProtocol,
  }) {
    final signer = _payloadSigner;
    final diagnostics = PayloadSigningDiagnostics.evaluate(
      featureFlags: _featureFlags,
      config: _payloadSigningConfig,
    );
    final diagnostic = <String, dynamic>{
      'stage': stage,
      'outgoing_signing_enabled': _featureFlags.enablePayloadSigning,
      'incoming_signature_required_before_negotiation': _featureFlags.requireIncomingPayloadSignatures,
      'signer_configured': signer != null,
      'active_key_id': signer?.activeKeyId,
      'key_count': signer?.keyCount ?? 0,
      'key_source': _payloadSigningConfig.sourceName,
      'secure_storage_available': _payloadSigningConfig.secureStorageAvailable,
      'health': diagnostics.toJson(),
      if (hasReceivedCapabilities) ...{
        'negotiated_signature_required': currentProtocol.signatureRequired,
        'negotiated_signature_algorithms': currentProtocol.signatureAlgorithms,
      },
      if (diagnostics.issues.isNotEmpty) 'warnings': diagnostics.issues.map((issue) => issue.code).toList(),
    };
    _logMessage('SECURITY', 'payload_signing:diagnostic', diagnostic);
    if (diagnostics.hasBlockingIssue && _diagnosticLogLimiter.shouldLog('payload_signing_blocking_issue')) {
      AppLogger.warning(
        'Payload signing configuration has blocking issues '
        '(status=${diagnostics.status.name}, source=${diagnostics.keySource}, '
        'secure_storage=${diagnostics.secureStorageAvailable}, '
        'issues=${diagnostics.issues.map((issue) => issue.code).join(",")})',
      );
    }
  }
}
