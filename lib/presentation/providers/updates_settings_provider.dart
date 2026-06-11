import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/update_check_inline_notice.dart';
import 'package:plug_agente/presentation/support/update_check_action_handler.dart';
import 'package:plug_agente/presentation/support/update_check_label_resolver.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';

class UpdatesSettingsProvider extends ChangeNotifier {
  UpdatesSettingsProvider(
    this._orchestrator, {
    RuntimeCapabilities? capabilities,
    RuntimeDetectionDiagnostics? runtimeDiagnostics,
    UpdateCheckLabelResolver? labelResolver,
    UpdateCheckActionHandler? actionHandler,
  }) : _capabilities = capabilities,
       _labelResolver = labelResolver ?? const UpdateCheckLabelResolver(),
       _actionHandler =
           actionHandler ??
           UpdateCheckActionHandler(
             orchestrator: _orchestrator,
             capabilities: capabilities,
             runtimeDiagnostics: runtimeDiagnostics,
           ) {
    _orchestratorChangesSubscription = _orchestrator.changes.listen((_) {
      unawaited(_onOrchestratorChanged());
    });
    unawaited(_onOrchestratorChanged());
  }

  final IAutoUpdateOrchestrator _orchestrator;
  final RuntimeCapabilities? _capabilities;
  final UpdateCheckLabelResolver _labelResolver;
  final UpdateCheckActionHandler _actionHandler;

  StreamSubscription<void>? _orchestratorChangesSubscription;
  bool _isDisposed = false;

  String _lastManualCheckDisplayLabel = '';
  bool _isCheckingUpdates = false;
  bool _hasPendingDownloadedUpdate = false;
  UpdateCheckInlineNotice? _updateCheckInlineNotice;

  IAutoUpdateOrchestrator get orchestrator => _orchestrator;

  bool get isAutoUpdateAvailable => _orchestrator.isAvailable;

  bool get updateNotificationsEnabled => _orchestrator.updateNotificationsEnabled;

  bool get automaticSilentUpdatesEnabled => _orchestrator.automaticSilentUpdatesEnabled;

  bool get isCheckingUpdates => _isCheckingUpdates;

  bool get isCheckingAutomaticUpdates => _orchestrator.isSilentCheckInProgress;

  bool get hasPendingDownloadedUpdate => _hasPendingDownloadedUpdate;

  UpdateCheckInlineNotice? get updateCheckInlineNotice => _updateCheckInlineNotice;

  String get appVersion => AppConstants.appVersion;

  String? get releaseNotes =>
      _orchestrator.lastManualDiagnostics?.releaseNotes ?? _orchestrator.lastAutomaticDiagnostics?.releaseNotes;

  String? get releaseNotesUrl =>
      _orchestrator.lastManualDiagnostics?.releaseNotesUrl ?? _orchestrator.lastAutomaticDiagnostics?.releaseNotesUrl;

  String lastUpdateCheckLabel(AppLocalizations l10n) => _labelResolver.lastUpdateCheckLabel(
    l10n: l10n,
    manualCheckDisplayLabel: _lastManualCheckDisplayLabel,
    lastManualDiagnostics: _orchestrator.lastManualDiagnostics,
    lastBackgroundDiagnostics: _orchestrator.lastBackgroundDiagnostics,
  );

  String lastBackgroundUpdateLabel(AppLocalizations l10n) =>
      _labelResolver.lastBackgroundUpdateLabel(l10n: l10n, orchestrator: _orchestrator);

  String lastAutomaticUpdateLabel(AppLocalizations l10n) =>
      _labelResolver.lastAutomaticUpdateLabel(l10n: l10n, orchestrator: _orchestrator);

  String autoUpdateFeedStatusLabel(AppLocalizations l10n) => _labelResolver.autoUpdateFeedStatusLabel(l10n);

  String? pendingUpdateNotice(AppLocalizations l10n) => _labelResolver.pendingUpdateNotice(
    l10n: l10n,
    orchestrator: _orchestrator,
    hasPendingDownloadedUpdate: _hasPendingDownloadedUpdate,
  );

  String? autoUpdateUnavailableMessage(AppLocalizations l10n) => _labelResolver.autoUpdateUnavailableMessage(
    l10n: l10n,
    isAutoUpdateAvailable: isAutoUpdateAvailable,
    capabilities: _capabilities,
  );

  Future<void> checkUpdates(BuildContext context) async {
    if (_isCheckingUpdates) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (!_orchestrator.isAvailable) {
      SettingsFeedback.showError(
        context: context,
        title: l10n.gsSectionUpdates,
        message: _actionHandler.unavailableMessage(l10n),
      );
      return;
    }

    final start = _actionHandler.beginManualCheck(l10n);
    _isCheckingUpdates = true;
    _updateCheckInlineNotice = null;
    _lastManualCheckDisplayLabel = start.checkingLabel;
    _notifyIfActive();

    final completion = await _actionHandler.runManualCheck(l10n);

    if (_isDisposed || !context.mounted) {
      return;
    }

    _isCheckingUpdates = false;
    _applyManualCompletion(completion);
    _notifyIfActive();

    await _actionHandler.presentManualCompletion(
      context: context,
      l10n: l10n,
      completion: completion,
      onCopyDiagnostics: () => copyUpdateDiagnostics(context),
    );
  }

  Future<void> checkAutomaticUpdatesNow(BuildContext context) async {
    if (_orchestrator.isSilentCheckInProgress) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (!_orchestrator.isAvailable) {
      SettingsFeedback.showError(
        context: context,
        title: l10n.gsSectionUpdates,
        message: _actionHandler.unavailableMessage(l10n),
      );
      return;
    }

    _updateCheckInlineNotice = null;
    _notifyIfActive();

    final completion = await _actionHandler.runAutomaticCheck(l10n);

    if (_isDisposed || !context.mounted) {
      return;
    }

    _applyAutomaticCompletion(completion);
    _notifyIfActive();

    await _actionHandler.presentAutomaticCompletion(
      context: context,
      l10n: l10n,
      completion: completion,
      onCopyDiagnostics: () => copyUpdateDiagnostics(context),
    );
  }

  Future<void> copyUpdateDiagnostics(BuildContext context) => _actionHandler.copyDiagnosticsToClipboard(context);

  Future<void> setUpdateNotificationsEnabled(BuildContext context, bool value) =>
      _actionHandler.setUpdateNotificationsEnabled(
        context,
        value,
        onSuccess: _onOrchestratorChanged,
      );

  Future<void> applyManualOnlyUpdateMode(BuildContext context) => _actionHandler.applyManualOnlyUpdateMode(
    context,
    onSuccess: _onOrchestratorChanged,
  );

  Future<void> setAutomaticSilentUpdatesEnabled(BuildContext context, bool value) =>
      _actionHandler.setAutomaticSilentUpdatesEnabled(
        context,
        value,
        onSuccess: _onOrchestratorChanged,
      );

  @override
  void dispose() {
    _isDisposed = true;
    _orchestratorChangesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onOrchestratorChanged() async {
    final hasPending = await _orchestrator.hasPendingDownloadedUpdate;
    if (_isDisposed) {
      return;
    }
    _hasPendingDownloadedUpdate = hasPending;
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _applyManualCompletion(UpdateCheckManualCompletion completion) {
    switch (completion) {
      case final UpdateCheckManualSuccess success:
        _lastManualCheckDisplayLabel = success.manualCheckDisplayLabel;
        _updateCheckInlineNotice = success.inlineNotice;
      case final UpdateCheckManualFailure failure:
        _lastManualCheckDisplayLabel = failure.manualCheckDisplayLabel;
    }
  }

  void _applyAutomaticCompletion(UpdateCheckAutomaticCompletion completion) {
    if (completion case final UpdateCheckAutomaticSuccess success) {
      _updateCheckInlineNotice = success.inlineNotice;
    }
  }
}
