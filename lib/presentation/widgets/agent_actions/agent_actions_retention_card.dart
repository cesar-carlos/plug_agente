import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsRetentionCard extends StatefulWidget {
  const AgentActionsRetentionCard({
    required this.l10n,
    super.key,
  });

  final AppLocalizations l10n;

  @override
  State<AgentActionsRetentionCard> createState() => _AgentActionsRetentionCardState();
}

class _AgentActionsRetentionCardState extends State<AgentActionsRetentionCard> {
  late final AgentActionRetentionSettings _settings;
  late final TextEditingController _executionDaysController;
  late final TextEditingController _auditDaysController;
  late final TextEditingController _capturedHoursController;

  bool _isSaving = false;
  String? _validationMessage;

  AppLocalizations get l10n => widget.l10n;

  @override
  void initState() {
    super.initState();
    _settings = getIt<AgentActionRetentionSettings>();
    _executionDaysController = TextEditingController(
      text: '${_settings.executionRetentionDays}',
    );
    _auditDaysController = TextEditingController(
      text: '${_settings.remoteAuditRetentionDays}',
    );
    _capturedHoursController = TextEditingController(
      text: '${_settings.capturedOutputRetentionHours}',
    );
  }

  @override
  void dispose() {
    _executionDaysController.dispose();
    _auditDaysController.dispose();
    _capturedHoursController.dispose();
    super.dispose();
  }

  void _reloadFromSettings() {
    _executionDaysController.text = '${_settings.executionRetentionDays}';
    _auditDaysController.text = '${_settings.remoteAuditRetentionDays}';
    _capturedHoursController.text = '${_settings.capturedOutputRetentionHours}';
  }

  Future<void> _restoreEnvironmentDefaults() async {
    setState(() {
      _isSaving = true;
      _validationMessage = null;
    });

    await _settings.clearPersistedOverrides();

    if (!mounted) {
      return;
    }

    _reloadFromSettings();
    setState(() {
      _isSaving = false;
    });

    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(l10n.agentActionsRetentionClearedTitle),
        content: Text(l10n.agentActionsRetentionClearedMessage),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  Future<void> _save() async {
    final executionDays = int.tryParse(_executionDaysController.text.trim());
    final auditDays = int.tryParse(_auditDaysController.text.trim());
    final capturedHours = int.tryParse(_capturedHoursController.text.trim());

    if (executionDays == null || auditDays == null || capturedHours == null) {
      setState(() {
        _validationMessage = l10n.agentActionsRetentionInvalidValue;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationMessage = null;
    });

    await _settings.save(
      executionDays: executionDays,
      remoteAuditDays: auditDays,
      capturedOutputHours: capturedHours,
    );

    if (!mounted) {
      return;
    }

    _reloadFromSettings();
    setState(() {
      _isSaving = false;
    });

    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(l10n.agentActionsRetentionSavedTitle),
        content: Text(l10n.agentActionsRetentionSavedMessage),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agentActionsRetentionTitle, style: context.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.agentActionsRetentionDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackFields = constraints.maxWidth < 720;
              final executionField = AppTextField(
                label: l10n.agentActionsRetentionExecutionHistory,
                controller: _executionDaysController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
              );
              final auditField = AppTextField(
                label: l10n.agentActionsRetentionRemoteAudit,
                controller: _auditDaysController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
              );
              final capturedField = AppTextField(
                label: l10n.agentActionsRetentionCapturedOutput,
                controller: _capturedHoursController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
              );

              if (stackFields) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    executionField,
                    const SizedBox(height: AppSpacing.sm),
                    auditField,
                    const SizedBox(height: AppSpacing.sm),
                    capturedField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: executionField),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: auditField),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: capturedField),
                ],
              );
            },
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsValidationTitle),
              content: Text(_validationMessage!),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSaving)
                      const SizedBox.square(
                        dimension: 14,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    else
                      const Icon(FluentIcons.save, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l10n.agentActionsRetentionSave),
                  ],
                ),
              ),
              Button(
                onPressed: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _validationMessage = null;
                        });
                        _reloadFromSettings();
                      },
                child: Text(l10n.agentActionsRetentionReset),
              ),
              if (_settings.hasPersistedOverrides)
                Button(
                  onPressed: _isSaving ? null : _restoreEnvironmentDefaults,
                  child: Text(l10n.agentActionsRetentionUseEnvDefaults),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.agentActionsRetentionEnvVariables,
            style: context.captionText,
          ),
          if (_settings.hasPersistedOverrides) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.agentActionsRetentionPersistedHint,
              style: context.captionText,
            ),
          ],
        ],
      ),
    );
  }
}
