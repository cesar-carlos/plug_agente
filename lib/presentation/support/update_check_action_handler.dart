import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/support/runtime_support_diagnostics_builder.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/core/support/support_diagnostics_text_formatter.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/update_check_inline_notice.dart';
import 'package:plug_agente/presentation/support/update_check_label_resolver.dart';
import 'package:plug_agente/presentation/support/update_support_diagnostics_builder.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:result_dart/result_dart.dart';
class UpdateCheckManualStart {
  UpdateCheckManualStart({
    required this.checkingLabel,
  });

  final String checkingLabel;
}

sealed class UpdateCheckManualCompletion {}

class UpdateCheckManualSuccess extends UpdateCheckManualCompletion {
  UpdateCheckManualSuccess({
    required this.manualCheckDisplayLabel,
    required this.diagnosticSections, this.inlineNotice,
    this.dialogMessage,
    this.dialogType = MessageType.info,
  });

  final String manualCheckDisplayLabel;
  final UpdateCheckInlineNotice? inlineNotice;
  final String? dialogMessage;
  final MessageType dialogType;
  final List<SupportDiagnosticsSection> diagnosticSections;
}

class UpdateCheckManualFailure extends UpdateCheckManualCompletion {
  UpdateCheckManualFailure({
    required this.manualCheckDisplayLabel,
    required this.dialogMessage,
    required this.diagnosticSections,
  });

  final String manualCheckDisplayLabel;
  final String dialogMessage;
  final List<SupportDiagnosticsSection> diagnosticSections;
}

sealed class UpdateCheckAutomaticCompletion {}

class UpdateCheckAutomaticSuccess extends UpdateCheckAutomaticCompletion {
  UpdateCheckAutomaticSuccess({
    required this.diagnosticSections, this.inlineNotice,
    this.dialogMessage,
    this.dialogType = MessageType.info,
  });

  final UpdateCheckInlineNotice? inlineNotice;
  final String? dialogMessage;
  final MessageType dialogType;
  final List<SupportDiagnosticsSection> diagnosticSections;
}

class UpdateCheckAutomaticFailure extends UpdateCheckAutomaticCompletion {
  UpdateCheckAutomaticFailure({
    required this.dialogMessage,
    required this.diagnosticSections,
  });

  final String dialogMessage;
  final List<SupportDiagnosticsSection> diagnosticSections;
}

class UpdateCheckActionHandler {
  UpdateCheckActionHandler({
    required IAutoUpdateOrchestrator orchestrator,
    RuntimeCapabilities? capabilities,
    RuntimeDetectionDiagnostics? runtimeDiagnostics,
    UpdateSupportDiagnosticsBuilder diagnosticsBuilder = const UpdateSupportDiagnosticsBuilder(),
    UpdateCheckLabelResolver labelResolver = const UpdateCheckLabelResolver(),
    SupportDiagnosticsTextFormatter supportTextFormatter = const SupportDiagnosticsTextFormatter(),
    RuntimeSupportDiagnosticsBuilder runtimeDiagnosticsBuilder = const RuntimeSupportDiagnosticsBuilder(),
  }) : _orchestrator = orchestrator,
       _capabilities = capabilities,
       _runtimeDiagnostics = runtimeDiagnostics,
       _diagnosticsBuilder = diagnosticsBuilder,
       _labelResolver = labelResolver,
       _supportTextFormatter = supportTextFormatter,
       _runtimeDiagnosticsBuilder = runtimeDiagnosticsBuilder;

  final IAutoUpdateOrchestrator _orchestrator;
  final RuntimeCapabilities? _capabilities;
  final RuntimeDetectionDiagnostics? _runtimeDiagnostics;
  final UpdateSupportDiagnosticsBuilder _diagnosticsBuilder;
  final UpdateCheckLabelResolver _labelResolver;
  final SupportDiagnosticsTextFormatter _supportTextFormatter;
  final RuntimeSupportDiagnosticsBuilder _runtimeDiagnosticsBuilder;

  String get appVersion => AppConstants.appVersion;

  UpdateCheckManualStart beginManualCheck(AppLocalizations l10n) {
    return UpdateCheckManualStart(checkingLabel: l10n.configUpdatesChecking);
  }

  Future<UpdateCheckManualCompletion> runManualCheck(AppLocalizations l10n) async {
    final result = await _orchestrator.checkManual();

    return result.fold(
      (outcome) {
        final sections = buildDiagnosticSections(l10n);
        final manualCheckDisplayLabel = _manualCheckDisplayLabelAfterOutcome(l10n, outcome);

        switch (outcome) {
          case ManualCheckOutcome.updateAvailable:
            return UpdateCheckManualSuccess(
              manualCheckDisplayLabel: manualCheckDisplayLabel,
              dialogMessage: l10n.configUpdatesAvailable,
              dialogType: MessageType.success,
              diagnosticSections: sections,
            );
          case ManualCheckOutcome.noUpdate:
            return UpdateCheckManualSuccess(
              manualCheckDisplayLabel: manualCheckDisplayLabel,
              inlineNotice: UpdateCheckInlineNotice(
                message: l10n.configUpdatesNotAvailable,
                hint: l10n.configUpdatesNotAvailableHint,
                severity: InfoBarSeverity.success,
                diagnosticSections: sections,
              ),
              diagnosticSections: sections,
            );
          case ManualCheckOutcome.triggerTimeout:
          case ManualCheckOutcome.completionTimeout:
          case ManualCheckOutcome.circuitOpen:
          case ManualCheckOutcome.notInitialized:
          case ManualCheckOutcome.disabled:
            return UpdateCheckManualSuccess(
              manualCheckDisplayLabel: manualCheckDisplayLabel,
              dialogMessage: UpdateSupportDiagnosticsBuilder.formatCompletionSource(
                l10n,
                _orchestrator.lastManualDiagnostics?.completionSource,
              ),
              dialogType: MessageType.warning,
              diagnosticSections: sections,
            );
        }
      },
      (failure) => UpdateCheckManualFailure(
        manualCheckDisplayLabel: '',
        dialogMessage: failure.toDisplayMessage(),
        diagnosticSections: buildDiagnosticSections(l10n),
      ),
    );
  }

  Future<UpdateCheckAutomaticCompletion> runAutomaticCheck(AppLocalizations l10n) async {
    final result = await _orchestrator.checkSilently();

    return result.fold(
      (outcome) {
        final sections = buildDiagnosticSections(
          l10n,
          automaticDiagnostics: _orchestrator.lastAutomaticDiagnostics,
        );
        final completionMessage = UpdateSupportDiagnosticsBuilder.formatCompletionSource(
          l10n,
          _orchestrator.lastAutomaticDiagnostics?.completionSource,
        );

        switch (outcome) {
          case SilentUpdateOutcome.installerReady:
          case SilentUpdateOutcome.requiresUserConsent:
            return UpdateCheckAutomaticSuccess(
              dialogMessage: completionMessage,
              dialogType: MessageType.warning,
              diagnosticSections: sections,
            );
          case SilentUpdateOutcome.noNewVersion:
            return UpdateCheckAutomaticSuccess(
              inlineNotice: UpdateCheckInlineNotice(
                message: l10n.configUpdatesNotAvailable,
                hint: l10n.configUpdatesNotAvailableHint,
                severity: InfoBarSeverity.success,
                diagnosticSections: sections,
              ),
              diagnosticSections: sections,
            );
          case SilentUpdateOutcome.silentDisabled:
          case SilentUpdateOutcome.rolloutSkipped:
          case SilentUpdateOutcome.cooldownActive:
          case SilentUpdateOutcome.pendingInProgress:
          case SilentUpdateOutcome.alreadyInProgress:
          case SilentUpdateOutcome.cancelled:
          case SilentUpdateOutcome.skippedByQuietHours:
            return UpdateCheckAutomaticSuccess(
              inlineNotice: UpdateCheckInlineNotice(
                message: completionMessage,
                severity: InfoBarSeverity.info,
                diagnosticSections: sections,
              ),
              diagnosticSections: sections,
            );
        }
      },
      (failure) => UpdateCheckAutomaticFailure(
        dialogMessage: failure.toDisplayMessage(),
        diagnosticSections: buildDiagnosticSections(
          l10n,
          automaticDiagnostics: _orchestrator.lastAutomaticDiagnostics,
        ),
      ),
    );
  }

  List<SupportDiagnosticsSection> buildDiagnosticSections(
    AppLocalizations l10n, {
    UpdateCheckDiagnostics? manualDiagnostics,
    UpdateCheckDiagnostics? backgroundDiagnostics,
    UpdateCheckDiagnostics? automaticDiagnostics,
  }) {
    return _diagnosticsBuilder.buildSections(
      l10n: l10n,
      currentAppVersion: appVersion,
      manualDiagnostics: manualDiagnostics ?? _orchestrator.lastManualDiagnostics,
      backgroundDiagnostics: backgroundDiagnostics ?? _orchestrator.lastBackgroundDiagnostics,
      automaticDiagnostics: automaticDiagnostics ?? _orchestrator.lastAutomaticDiagnostics,
    );
  }

  String buildSupportDiagnosticsText(AppLocalizations l10n) {
    final sections = <SupportDiagnosticsSection>[
      SupportDiagnosticsSection(
        title: 'Plug Agente Auto-Update',
        fields: <SupportDiagnosticsField>[
          SupportDiagnosticsField(
            key: l10n.gsLabelVersion,
            value: appVersion,
          ),
        ],
      ),
      if (_buildRuntimeSupportDiagnostics() case final SupportDiagnosticsSection runtimeSection) runtimeSection,
      ..._diagnosticsBuilder.buildSections(
        l10n: l10n,
        currentAppVersion: appVersion,
        manualDiagnostics: _orchestrator.lastManualDiagnostics,
        backgroundDiagnostics: _orchestrator.lastBackgroundDiagnostics,
        automaticDiagnostics: _orchestrator.lastAutomaticDiagnostics,
        updateNotificationsEnabled: _orchestrator.updateNotificationsEnabled,
        automaticSilentUpdatesEnabled: _orchestrator.automaticSilentUpdatesEnabled,
      ),
    ];

    return _supportTextFormatter.formatSections(sections);
  }

  String unavailableMessage(AppLocalizations l10n) {
    return _labelResolver.autoUpdateUnavailableMessage(
          l10n: l10n,
          isAutoUpdateAvailable: _orchestrator.isAvailable,
          capabilities: _capabilities,
        ) ??
        l10n.configAutoUpdateNotSupported;
  }

  Future<void> copyDiagnosticsToClipboard(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final diagnostics = buildSupportDiagnosticsText(l10n);
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!context.mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(l10n.configUpdateDiagnosticsCopied),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  Future<void> setUpdateNotificationsEnabled(
    BuildContext context,
    bool value, {
    required Future<void> Function() onSuccess,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    await _applyPreferenceChange(
      context: context,
      l10n: l10n,
      apply: () => _orchestrator.setUpdateNotificationsEnabled(value),
      onSuccess: onSuccess,
      successTitle: value ? l10n.configUpdateNotificationsEnabled : l10n.configUpdateNotificationsDisabled,
    );
  }

  Future<void> applyManualOnlyUpdateMode(
    BuildContext context, {
    required Future<void> Function() onSuccess,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    await _applyPreferenceChange(
      context: context,
      l10n: l10n,
      apply: _orchestrator.applyManualOnlyUpdateMode,
      onSuccess: onSuccess,
      successTitle: l10n.configManualOnlyUpdatesApplied,
    );
  }

  Future<void> setAutomaticSilentUpdatesEnabled(
    BuildContext context,
    bool value, {
    required Future<void> Function() onSuccess,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _orchestrator.setAutomaticSilentUpdatesEnabled(value);
    if (!context.mounted) {
      return;
    }

    result.fold(
      (_) async {
        await onSuccess();
        if (!context.mounted) {
          return;
        }
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(
              value ? l10n.configAutomaticSilentUpdatesEnabled : l10n.configAutomaticSilentUpdatesDisabled,
            ),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
        if (!value && _orchestrator.updateNotificationsEnabled) {
          displayInfoBar(
            context,
            builder: (context, close) => InfoBar(
              title: Text(l10n.configAutomaticSilentUpdatesDisabled),
              content: Text(l10n.configAutomaticSilentUpdatesDisableNotificationsHint),
              onClose: close,
            ),
          );
        }
      },
      (failure) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: failure.toDisplayMessage(),
        );
      },
    );
  }

  Future<void> _applyPreferenceChange({
    required BuildContext context,
    required AppLocalizations l10n,
    required Future<Result<void>> Function() apply,
    required Future<void> Function() onSuccess,
    required String successTitle,
  }) async {
    final result = await apply();
    if (!context.mounted) {
      return;
    }

    result.fold(
      (_) async {
        await onSuccess();
        if (!context.mounted) {
          return;
        }
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(successTitle),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      },
      (failure) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: failure.toDisplayMessage(),
        );
      },
    );
  }

  Future<void> presentManualCompletion({
    required BuildContext context,
    required AppLocalizations l10n,
    required UpdateCheckManualCompletion completion,
    required Future<void> Function() onCopyDiagnostics,
  }) async {
    switch (completion) {
      case final UpdateCheckManualSuccess success when success.dialogMessage != null:
        await _showUpdateDiagnosticsDialog(
          context: context,
          l10n: l10n,
          message: success.dialogMessage!,
          sections: success.diagnosticSections,
          type: success.dialogType,
          onCopyDiagnostics: onCopyDiagnostics,
        );
      case final UpdateCheckManualFailure failure:
        await _showUpdateDiagnosticsDialog(
          context: context,
          l10n: l10n,
          message: failure.dialogMessage,
          sections: failure.diagnosticSections,
          type: MessageType.error,
          onCopyDiagnostics: onCopyDiagnostics,
        );
      case UpdateCheckManualSuccess():
        break;
    }
  }

  Future<void> presentAutomaticCompletion({
    required BuildContext context,
    required AppLocalizations l10n,
    required UpdateCheckAutomaticCompletion completion,
    required Future<void> Function() onCopyDiagnostics,
  }) async {
    switch (completion) {
      case final UpdateCheckAutomaticSuccess success when success.dialogMessage != null:
        await _showUpdateDiagnosticsDialog(
          context: context,
          l10n: l10n,
          message: success.dialogMessage!,
          sections: success.diagnosticSections,
          type: success.dialogType,
          onCopyDiagnostics: onCopyDiagnostics,
        );
      case final UpdateCheckAutomaticFailure failure:
        await _showUpdateDiagnosticsDialog(
          context: context,
          l10n: l10n,
          message: failure.dialogMessage,
          sections: failure.diagnosticSections,
          type: MessageType.error,
          onCopyDiagnostics: onCopyDiagnostics,
        );
      case UpdateCheckAutomaticSuccess():
        break;
    }
  }

  String _manualCheckDisplayLabelAfterOutcome(AppLocalizations l10n, ManualCheckOutcome outcome) {
    if (!_isSuccessfulManualOutcome(outcome)) {
      return '';
    }
    final checkedAt = UpdateCheckLabelResolver.formatCheckedAt(DateTime.now());
    return '${l10n.configLastUpdatePrefix}$checkedAt';
  }

  bool _isSuccessfulManualOutcome(ManualCheckOutcome outcome) {
    return switch (outcome) {
      ManualCheckOutcome.updateAvailable || ManualCheckOutcome.noUpdate => true,
      _ => false,
    };
  }

  SupportDiagnosticsSection? _buildRuntimeSupportDiagnostics() {
    final capabilities = _capabilities;
    if (capabilities == null) {
      return null;
    }

    return _runtimeDiagnosticsBuilder.buildSection(
      capabilities: capabilities,
      diagnostics: _runtimeDiagnostics,
    );
  }

  Future<void> _showUpdateDiagnosticsDialog({
    required BuildContext context,
    required AppLocalizations l10n,
    required String message,
    required List<SupportDiagnosticsSection> sections,
    required Future<void> Function() onCopyDiagnostics,
    MessageType type = MessageType.info,
  }) {
    return SettingsFeedback.showWithDiagnostics(
      context: context,
      title: l10n.gsSectionUpdates,
      message: message,
      type: type,
      diagnosticSections: sections,
      onCopyDiagnostics: onCopyDiagnostics,
      collapseDiagnosticsByDefault: type == MessageType.info,
    );
  }
}
