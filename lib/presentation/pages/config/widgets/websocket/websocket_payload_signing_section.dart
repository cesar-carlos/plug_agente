import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/config/payload_signing_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';
import 'package:provider/provider.dart';

class WebSocketPayloadSigningSection extends StatefulWidget {
  const WebSocketPayloadSigningSection({super.key});

  @override
  State<WebSocketPayloadSigningSection> createState() => _WebSocketPayloadSigningSectionState();
}

class _WebSocketPayloadSigningSectionState extends State<WebSocketPayloadSigningSection> {
  late bool _outgoingSigningEnabled;
  late bool _incomingSignatureRequired;
  bool _isPersistingOutgoing = false;
  bool _isPersistingIncoming = false;

  PayloadSigningDiagnostics? _cachedDiagnostics;
  Object? _cachedDiagnosticsKey;

  FeatureFlags get _flags => context.read<FeatureFlags>();
  PayloadSigningConfig get _config => context.read<PayloadSigningConfig>();

  @override
  void initState() {
    super.initState();
    final flags = context.read<FeatureFlags>();
    _outgoingSigningEnabled = flags.enablePayloadSigning;
    _incomingSignatureRequired = flags.requireIncomingPayloadSignatures;
  }

  PayloadSigningDiagnostics _diagnostics() {
    final flags = _flags;
    final config = _config;
    final cacheKey = (
      flags.enablePayloadSigning,
      flags.requireIncomingPayloadSignatures,
      config.activeKeyId,
      config.keyCount,
      config.source,
      config.secureStorageAvailable,
      config.warnings.length,
    );
    final cached = _cachedDiagnostics;
    if (cached != null && _cachedDiagnosticsKey == cacheKey) {
      return cached;
    }
    final next = PayloadSigningDiagnostics.evaluate(
      featureFlags: flags,
      config: config,
    );
    _cachedDiagnostics = next;
    _cachedDiagnosticsKey = cacheKey;
    return next;
  }

  Future<void> _setOutgoingSigning(bool value) async {
    if (_isPersistingOutgoing) {
      return;
    }
    setState(() {
      _isPersistingOutgoing = true;
      _outgoingSigningEnabled = value;
    });
    try {
      await _flags.setEnablePayloadSigning(value);
    } finally {
      if (mounted) {
        setState(() {
          _isPersistingOutgoing = false;
          _outgoingSigningEnabled = _flags.enablePayloadSigning;
          _cachedDiagnostics = null;
          _cachedDiagnosticsKey = null;
        });
      }
    }
  }

  Future<void> _setIncomingSignatureRequired(bool value) async {
    if (_isPersistingIncoming) {
      return;
    }
    setState(() {
      _isPersistingIncoming = true;
      _incomingSignatureRequired = value;
    });
    try {
      await _flags.setRequireIncomingPayloadSignatures(value);
    } finally {
      if (mounted) {
        setState(() {
          _isPersistingIncoming = false;
          _incomingSignatureRequired = _flags.requireIncomingPayloadSignatures;
          _cachedDiagnostics = null;
          _cachedDiagnosticsKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final diagnostics = _diagnostics();
    return AppCard(
      child: SettingsSectionBlock(
        title: l10n.wsSectionPayloadSigning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (diagnostics.issues.isNotEmpty) ...[
              InfoBar(
                title: Text(_localizeStatusTitle(l10n, diagnostics.status)),
                content: Text(
                  diagnostics.issues.map((issue) => _localizeIssue(l10n, issue)).join('\n'),
                ),
                severity: _statusSeverity(diagnostics.status),
                isLong: true,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _SigningMeta(
                  label: l10n.wsPayloadSigningMetaSigner,
                  value: diagnostics.signerConfigured
                      ? l10n.wsPayloadSigningSignerConfigured
                      : l10n.wsPayloadSigningSignerMissing,
                ),
                _SigningMeta(
                  label: l10n.wsPayloadSigningMetaActiveKey,
                  value: diagnostics.activeKeyId ?? l10n.wsPayloadSigningActiveKeyNone,
                ),
                _SigningMeta(
                  label: l10n.wsPayloadSigningMetaKeys,
                  value: diagnostics.keyCount.toString(),
                ),
                _SigningMeta(
                  label: l10n.wsPayloadSigningMetaSource,
                  value: _localizeSource(l10n, _config.source),
                ),
                _SigningMeta(
                  label: l10n.wsPayloadSigningMetaRotation,
                  value: diagnostics.rotationReady
                      ? l10n.wsPayloadSigningRotationReady
                      : l10n.wsPayloadSigningRotationSingleKey,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ToggleSwitch(
              checked: _outgoingSigningEnabled,
              onChanged: _isPersistingOutgoing ? null : (bool value) => unawaited(_setOutgoingSigning(value)),
              content: Text(l10n.wsPayloadSigningToggleOutgoing),
            ),
            const SizedBox(height: AppSpacing.sm),
            ToggleSwitch(
              checked: _incomingSignatureRequired,
              onChanged: _isPersistingIncoming ? null : (bool value) => unawaited(_setIncomingSignatureRequired(value)),
              content: Text(l10n.wsPayloadSigningToggleIncoming),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.wsPayloadSigningHelp,
              style: context.captionText,
            ),
          ],
        ),
      ),
    );
  }

  String _localizeStatusTitle(AppLocalizations l10n, PayloadSigningHealthStatus status) {
    return switch (status) {
      PayloadSigningHealthStatus.ok => l10n.wsPayloadSigningStatusOk,
      PayloadSigningHealthStatus.warning => l10n.wsPayloadSigningStatusWarning,
      PayloadSigningHealthStatus.error => l10n.wsPayloadSigningStatusError,
    };
  }

  InfoBarSeverity _statusSeverity(PayloadSigningHealthStatus status) {
    return switch (status) {
      PayloadSigningHealthStatus.ok => InfoBarSeverity.success,
      PayloadSigningHealthStatus.warning => InfoBarSeverity.warning,
      PayloadSigningHealthStatus.error => InfoBarSeverity.error,
    };
  }

  String _localizeIssue(AppLocalizations l10n, PayloadSigningHealthIssue issue) {
    return switch (issue.code) {
      'payload_signing_enabled_without_key' => l10n.wsPayloadSigningIssueEnabledWithoutKey,
      'incoming_signatures_required_without_key' => l10n.wsPayloadSigningIssueIncomingRequiredWithoutKey,
      'payload_signing_active_key_missing' => l10n.wsPayloadSigningIssueActiveKeyMissing,
      'payload_signing_active_key_not_found' => l10n.wsPayloadSigningIssueActiveKeyNotFound,
      'payload_signing_secure_storage_unavailable' => l10n.wsPayloadSigningIssueSecureStorageUnavailable,
      'payload_signing_rotation_single_key' => l10n.wsPayloadSigningIssueRotationSingleKey,
      'payload_signing_config_not_registered' => l10n.wsPayloadSigningIssueConfigNotRegistered,
      _ => l10n.wsPayloadSigningIssueGenericWarning(issue.code),
    };
  }

  String _localizeSource(AppLocalizations l10n, PayloadSigningConfigSource source) {
    return switch (source) {
      PayloadSigningConfigSource.none => l10n.wsPayloadSigningSourceNone,
      PayloadSigningConfigSource.environment => l10n.wsPayloadSigningSourceEnvironment,
      PayloadSigningConfigSource.secureStorage => l10n.wsPayloadSigningSourceSecureStorage,
      PayloadSigningConfigSource.environmentAndSecureStorage => l10n.wsPayloadSigningSourceEnvironmentAndSecureStorage,
    };
  }
}

class _SigningMeta extends StatelessWidget {
  const _SigningMeta({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: context.bodyMuted),
          TextSpan(
            text: value,
            style: context.bodyText.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      semanticsLabel: '$label: $value',
    );
  }
}
