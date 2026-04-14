import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

/// Advanced diagnostics toggles (may log sensitive SQL). Requires dependency
/// injection setup so the service locator is ready.
class DiagnosticsConfigSection extends StatefulWidget {
  const DiagnosticsConfigSection({super.key});

  @override
  State<DiagnosticsConfigSection> createState() => _DiagnosticsConfigSectionState();
}

class _DiagnosticsConfigSectionState extends State<DiagnosticsConfigSection> {
  late final FeatureFlags _flags = getIt<FeatureFlags>();
  late final HubResilienceConfig _hubResilience = getIt<HubResilienceConfig>();
  late bool _odbcPaginatedSqlLog;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _hubMaxTicksController = TextEditingController();
  final TextEditingController _hubIntervalSecondsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _odbcPaginatedSqlLog = _flags.enableOdbcPaginatedSqlDebugLog;
    _reloadHubReconnectFields();
  }

  void _reloadHubReconnectFields() {
    _hubMaxTicksController.text = '${_hubResilience.maxFailedTicks}';
    _hubIntervalSecondsController.text = '${_hubResilience.persistentRetryInterval.inSeconds}';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hubMaxTicksController.dispose();
    _hubIntervalSecondsController.dispose();
    super.dispose();
  }

  Future<void> _setOdbcPaginatedSqlLog(bool value) async {
    setState(() => _odbcPaginatedSqlLog = value);
    await _flags.setEnableOdbcPaginatedSqlDebugLog(value);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _applyHubReconnect(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final maxTicks = int.tryParse(_hubMaxTicksController.text.trim());
    if (maxTicks == null || maxTicks < 0) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: l10n.diagnosticsHubReconnectInvalidMaxTicks,
      );
      return;
    }
    final intervalSec = int.tryParse(_hubIntervalSecondsController.text.trim());
    if (intervalSec == null || intervalSec < 5 || intervalSec > 86400) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.modalTitleError,
        message: l10n.diagnosticsHubReconnectInvalidInterval,
      );
      return;
    }
    await _flags.setHubPersistentRetryMaxFailedTicksOverride(maxTicks);
    await _flags.setHubPersistentRetryIntervalSecondsOverride(intervalSec);
    _reloadHubReconnectFields();
    if (!context.mounted) {
      return;
    }
    await SettingsFeedback.showSuccess(
      context: context,
      title: l10n.modalTitleConfigSaved,
      message: l10n.diagnosticsHubReconnectSavedMessage,
    );
  }

  Future<void> _resetHubReconnect() async {
    await _flags.resetHubResilienceOverrides();
    _reloadHubReconnectFields();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SettingsSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSectionTitle(
                    title: l10n.diagnosticsSectionTitle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  InfoBar(
                    title: Text(l10n.diagnosticsWarningTitle),
                    content: Text(l10n.diagnosticsWarningBody),
                    severity: InfoBarSeverity.warning,
                    isLong: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsToggleTile(
                    label: l10n.diagnosticsOdbcPaginatedSqlLogLabel,
                    value: _odbcPaginatedSqlLog,
                    onChanged: (bool value) {
                      unawaited(_setOdbcPaginatedSqlLog(value));
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.diagnosticsOdbcPaginatedSqlLogDescription,
                    style: context.captionText,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SettingsSectionTitle(
                    title: l10n.diagnosticsHubReconnectSectionTitle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: l10n.diagnosticsHubReconnectMaxTicksLabel,
                    hint: l10n.diagnosticsHubReconnectMaxTicksHint,
                    controller: _hubMaxTicksController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: l10n.diagnosticsHubReconnectIntervalLabel,
                    hint: l10n.diagnosticsHubReconnectIntervalHint,
                    controller: _hubIntervalSecondsController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.diagnosticsHubReconnectEnvHint,
                    style: context.captionText,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      AppButton(
                        label: l10n.diagnosticsHubReconnectApply,
                        onPressed: () => unawaited(_applyHubReconnect(context)),
                      ),
                      AppButton(
                        label: l10n.diagnosticsHubReconnectReset,
                        isPrimary: false,
                        onPressed: () => unawaited(_resetHubReconnect()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
