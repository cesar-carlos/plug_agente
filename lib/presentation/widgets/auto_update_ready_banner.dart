import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/services/user_initiated_apply_failure.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/auto_update_banner_activity.dart';
import 'package:result_dart/result_dart.dart';

/// In-app banner shown across the app shell when a silent update either
/// finished downloading and is staged on disk, or was blocked from
/// downloading automatically because Windows UAC would prompt the user.
///
/// Two states share the same surface so the operator always sees a
/// single banner at the top of the FluentApp builder. The agent keeps
/// running normally underneath in both cases.
class AutoUpdateReadyBanner extends StatefulWidget {
  const AutoUpdateReadyBanner({super.key});

  @override
  State<AutoUpdateReadyBanner> createState() => _AutoUpdateReadyBannerState();
}

enum _BannerMode { pendingDownloaded, awaitingUserConsent }

class _AutoUpdateReadyBannerState extends State<AutoUpdateReadyBanner> {
  static const Duration _dismissTtl = Duration(hours: 6);

  IAutoUpdateOrchestrator? _orchestrator;
  IAppSettingsStore? _settingsStore;
  StreamSubscription<void>? _changesSubscription;
  AutoUpdateBannerActivity _activity = const AutoUpdateBannerIdle();
  String? _dismissedForVersion;
  DateTime? _dismissedUntil;

  /// Snapshot of the latest "has pending downloaded update" answer. The
  /// orchestrator getter is async now (it inspects on-disk artifacts
  /// through an injected reader); we hydrate this flag from
  /// [_handleChange] / [didChangeDependencies] so [build] stays
  /// synchronous and the rebuild path is jank-free.
  bool _hasPendingDownloaded = false;

  @override
  void initState() {
    super.initState();
    if (!getIt.isRegistered<IAutoUpdateOrchestrator>()) {
      return;
    }
    _orchestrator = getIt<IAutoUpdateOrchestrator>();
    _changesSubscription = _orchestrator!.changes.listen((_) => _handleChange());
    if (getIt.isRegistered<IAppSettingsStore>()) {
      _settingsStore = getIt<IAppSettingsStore>();
      _hydrateDismissState();
    }
    unawaited(_refreshPendingState());
  }

  void _hydrateDismissState() {
    final store = _settingsStore;
    if (store == null) return;
    final raw = store.getString(AppSettingsKeys.autoUpdateBannerDismiss);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final version = decoded['version'];
      final untilIso = decoded['until'];
      if (version is! String || untilIso is! String) return;
      final until = DateTime.tryParse(untilIso);
      if (until == null) return;
      _dismissedForVersion = version;
      _dismissedUntil = until;
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted banner dismiss state',
        name: 'auto_update_ready_banner',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    super.dispose();
  }

  void _handleChange() {
    if (!mounted) return;
    unawaited(_refreshPendingState());
  }

  Future<void> _refreshPendingState() async {
    final orchestrator = _orchestrator;
    if (orchestrator == null) return;
    final result = await orchestrator.hasPendingDownloadedUpdate;
    if (!mounted) return;
    if (_hasPendingDownloaded != result) {
      setState(() => _hasPendingDownloaded = result);
    } else {
      setState(() {});
    }
  }

  _BannerMode? get _mode {
    final orchestrator = _orchestrator;
    if (orchestrator == null) return null;
    if (_hasPendingDownloaded) return _BannerMode.pendingDownloaded;
    if (orchestrator.hasUpdateAwaitingUserConsent) return _BannerMode.awaitingUserConsent;
    return null;
  }

  bool get _shouldShow {
    final mode = _mode;
    if (mode == null) return false;
    final pendingVersion = _pendingVersion(_orchestrator!);
    if (pendingVersion == null) return false;
    if (_dismissedForVersion == pendingVersion) {
      final until = _dismissedUntil;
      if (until != null && DateTime.now().isBefore(until)) {
        return false;
      }
    }
    return true;
  }

  String? _pendingVersion(IAutoUpdateOrchestrator orchestrator) {
    final diagnostics = orchestrator.lastAutomaticDiagnostics;
    return diagnostics?.pendingVersion ?? diagnostics?.remoteVersion;
  }

  Future<void> _onPrimaryAction(AppLocalizations l10n, _BannerMode mode) async {
    final orchestrator = _orchestrator;
    if (orchestrator == null || _activity.isBusy) return;
    final version = _pendingVersion(orchestrator) ?? '';
    final confirmed = await _showConfirmDialog(l10n, version, mode);
    if (!mounted || confirmed != true) return;

    // The notification service does not get a localizations context, so
    // we materialize the body using the resolved delay from the orchestrator
    // (the default 30s is baked into the message when the resolver is
    // missing). Keep the parametrized version aligned with the toast
    // grace period defined in `resolveAutoUpdatePreCloseDelaySeconds`.
    final noticeTitle = l10n.configAutoUpdateClosingTitle;
    final noticeBody = l10n.configAutoUpdateClosingBody(_preCloseDelaySeconds);

    setState(() {
      // Pending-downloaded skips the download phase (already on disk);
      // the UAC-blocked path begins by downloading the installer.
      _activity = mode == _BannerMode.pendingDownloaded
          ? const AutoUpdateBannerStaging()
          : const AutoUpdateBannerDownloading();
    });

    final Result<void> result;
    if (mode == _BannerMode.pendingDownloaded) {
      result = await orchestrator.applyPendingSilentUpdate(
        noticeTitle: noticeTitle,
        noticeBody: noticeBody,
      );
    } else {
      result = await orchestrator.applyAvailableUpdate(
        noticeTitle: noticeTitle,
        noticeBody: noticeBody,
      );
    }
    if (!mounted) return;
    Exception? error;
    result.fold(
      (_) {},
      (failure) => error = failure,
    );
    if (error != null) {
      setState(() => _activity = const AutoUpdateBannerIdle());
      _showApplyError(l10n, error!);
      return;
    }
    // On success the helper close-and-launch is in flight; flip the
    // label one last time so the spinner reflects what is happening
    // while we wait for the app to terminate.
    if (mounted) {
      setState(() => _activity = const AutoUpdateBannerLaunching());
    }
  }

  void _onDefer(AppLocalizations l10n) {
    final orchestrator = _orchestrator;
    if (orchestrator == null) return;
    final version = _pendingVersion(orchestrator);
    if (version == null) return;
    final until = DateTime.now().add(_dismissTtl);
    setState(() {
      _dismissedForVersion = version;
      _dismissedUntil = until;
    });
    _persistDismiss(version, until);
  }

  Future<void> _persistDismiss(String version, DateTime until) async {
    final store = _settingsStore;
    if (store == null) return;
    final payload = jsonEncode(<String, dynamic>{
      'version': version,
      'until': until.toIso8601String(),
    });
    try {
      await store.setString(AppSettingsKeys.autoUpdateBannerDismiss, payload);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist banner dismiss state',
        name: 'auto_update_ready_banner',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool?> _showConfirmDialog(
    AppLocalizations l10n,
    String version,
    _BannerMode mode,
  ) {
    final title = mode == _BannerMode.pendingDownloaded
        ? l10n.autoUpdateReadyDialogTitle
        : l10n.autoUpdateConsentDialogTitle;
    final body = mode == _BannerMode.pendingDownloaded
        ? l10n.autoUpdateReadyDialogBody(version)
        : l10n.autoUpdateConsentDialogBody(version);
    final confirmLabel = mode == _BannerMode.pendingDownloaded
        ? l10n.autoUpdateReadyDialogConfirm
        : l10n.autoUpdateConsentDialogConfirm;
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.autoUpdateReadyDialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  void _showApplyError(AppLocalizations l10n, Exception error) {
    final message = _resolveApplyErrorMessage(l10n, error);
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(l10n.autoUpdateApplyFailureMessage),
          content: SelectableText(message),
          severity: InfoBarSeverity.error,
          onClose: close,
        );
      },
    );
  }

  /// Picks the most operator-friendly message for an apply failure.
  ///
  /// User-initiated apply failures are sealed
  /// ([UserInitiatedApplyFailure]); we pattern-match on the concrete
  /// subtype so adding a new outcome forces the compiler to surface the
  /// missing localisation branch. Infrastructure failures (e.g.
  /// network) fall back to `failure.message`, which already carries
  /// actionable text from the lower layer.
  String _resolveApplyErrorMessage(AppLocalizations l10n, Exception error) {
    if (error is UserInitiatedApplyFailure) {
      return switch (error) {
        UserInitiatedApplyCooldownActive() => l10n.autoUpdateApplyOutcomeCooldown,
        UserInitiatedApplySilentDisabled() => l10n.autoUpdateApplyOutcomeSilentDisabled,
        UserInitiatedApplyCancelled() => l10n.autoUpdateApplyOutcomeCancelled,
        UserInitiatedApplyQuietHours() => l10n.autoUpdateApplyOutcomeQuietHours,
        UserInitiatedApplyNoNewVersion() => l10n.autoUpdateApplyOutcomeNoNewVersion,
        UserInitiatedApplyAlreadyInProgress() => l10n.autoUpdateApplyOutcomeAlreadyInProgress,
        UserInitiatedApplyPendingInProgress() => l10n.autoUpdateApplyOutcomePendingInProgress,
        UserInitiatedApplyCouldNotPrepare() => l10n.autoUpdateApplyOutcomeUnknown,
      };
    }
    if (error is domain.Failure) return error.message;
    return l10n.autoUpdateApplyFailureMessage;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return const SizedBox.shrink();
    }
    final orchestrator = _orchestrator!;
    final mode = _mode!;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return const SizedBox.shrink();
    }
    final version = _pendingVersion(orchestrator) ?? '';
    final colors = context.appColors;
    final tone = mode == _BannerMode.pendingDownloaded ? AppFeedbackTone.info : AppFeedbackTone.warning;
    final feedback = colors.feedback(tone);
    final title = mode == _BannerMode.pendingDownloaded
        ? l10n.autoUpdateReadyBannerTitle
        : l10n.autoUpdateConsentBannerTitle;
    final body = mode == _BannerMode.pendingDownloaded
        ? l10n.autoUpdateReadyBannerBody(version)
        : l10n.autoUpdateConsentBannerBody(version);
    final primaryLabel = mode == _BannerMode.pendingDownloaded
        ? l10n.autoUpdateReadyBannerInstallNow
        : l10n.autoUpdateConsentBannerInstall;
    final iconData = mode == _BannerMode.pendingDownloaded ? FluentIcons.download : FluentIcons.shield_solid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: feedback.background,
        border: Border(
          bottom: BorderSide(color: feedback.border),
        ),
      ),
      child: Row(
        children: [
          Icon(
            iconData,
            color: feedback.accent,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.bodyText.copyWith(
                    fontWeight: FontWeight.w600,
                    color: feedback.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: context.captionText,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Button(
            onPressed: _activity.isBusy ? null : () => _onDefer(l10n),
            child: Text(l10n.autoUpdateReadyBannerDefer),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: _activity.isBusy ? null : () => _onPrimaryAction(l10n, mode),
            child: _activity.isBusy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(_activityLabel(l10n)),
                    ],
                  )
                : Text(primaryLabel),
          ),
        ],
      ),
    );
  }

  String _activityLabel(AppLocalizations l10n) {
    return switch (_activity) {
      AutoUpdateBannerDownloading() => l10n.autoUpdateApplyPhaseDownloading,
      AutoUpdateBannerStaging() => l10n.autoUpdateApplyPhaseStaging,
      AutoUpdateBannerLaunching() => l10n.autoUpdateApplyPhaseLaunching,
      // Idle never shows the spinner, so this branch is reached only
      // during the brief transition between user click and the first
      // setState that flips activity to Downloading/Staging.
      AutoUpdateBannerIdle() => l10n.autoUpdateApplyPhaseStaging,
    };
  }
}

/// Default pre-close delay used by the banner when calling the orchestrator.
/// Matches `_defaultPreCloseDelaySeconds` in
/// `lib/core/config/auto_update_feed_config.dart`. Duplicated here to avoid
/// pulling the config module into the widget; the resolver in the registrar
/// will still honor `AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS` overrides for the
/// actual delay between the toast and the close.
const int _preCloseDelaySeconds = 30;
