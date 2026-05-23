import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsPreflightSettingsCard extends StatefulWidget {
  const AgentActionsPreflightSettingsCard({
    required this.l10n,
    required this.provider,
    super.key,
  });

  final AppLocalizations l10n;
  final AgentActionsProvider provider;

  @override
  State<AgentActionsPreflightSettingsCard> createState() => _AgentActionsPreflightSettingsCardState();
}

class _AgentActionsPreflightSettingsCardState extends State<AgentActionsPreflightSettingsCard> {
  late final AgentActionPreflightSettings _settings;
  late final TextEditingController _daysController;

  bool _isSaving = false;
  String? _validationMessage;

  AppLocalizations get l10n => widget.l10n;

  @override
  void initState() {
    super.initState();
    _settings = getIt<AgentActionPreflightSettings>();
    _daysController = TextEditingController(text: '${_settings.validityDays}');
  }

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agentActionsPreflightSettingsTitle, style: context.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.agentActionsPreflightSettingsDescription,
            style: context.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: l10n.agentActionsPreflightSettingsValidityDays,
            controller: _daysController,
            enabled: widget.provider.isFeatureEnabled && !_isSaving,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.agentActionsPreflightSettingsEnvHint,
            style: context.bodyMuted,
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoBar(
              title: Text(l10n.agentActionsPreflightSettingsInvalidTitle),
              content: Text(_validationMessage!),
              severity: InfoBarSeverity.error,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: widget.provider.isFeatureEnabled && !_isSaving ? _onSave : null,
                child: Text(l10n.agentActionsPreflightSettingsSave),
              ),
              Button(
                onPressed: widget.provider.isFeatureEnabled && !_isSaving ? _onDiscard : null,
                child: Text(l10n.agentActionsPreflightSettingsDiscard),
              ),
              Button(
                onPressed: widget.provider.isFeatureEnabled && !_isSaving && _settings.hasPersistedOverride
                    ? _onUseEnvDefaults
                    : null,
                child: Text(l10n.agentActionsPreflightSettingsUseEnvDefaults),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onSave() async {
    final parsed = int.tryParse(_daysController.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() {
        _validationMessage = l10n.agentActionsPreflightSettingsInvalidValue;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationMessage = null;
    });
    await _settings.save(validityDays: parsed);
    if (!mounted) {
      return;
    }
    _daysController.text = '${_settings.validityDays}';
    setState(() {
      _isSaving = false;
    });
    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(l10n.agentActionsPreflightSettingsSavedTitle),
        content: Text(l10n.agentActionsPreflightSettingsSavedMessage),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
    widget.provider.notifyListeners();
  }

  void _onDiscard() {
    setState(() {
      _validationMessage = null;
      _daysController.text = '${_settings.validityDays}';
    });
  }

  Future<void> _onUseEnvDefaults() async {
    setState(() {
      _isSaving = true;
      _validationMessage = null;
    });
    await _settings.clearPersistedOverride();
    if (!mounted) {
      return;
    }
    _daysController.text = '${_settings.validityDays}';
    setState(() {
      _isSaving = false;
    });
    displayInfoBar(
      context,
      builder: (BuildContext closeContext, void Function() close) => InfoBar(
        title: Text(l10n.agentActionsPreflightSettingsClearedTitle),
        content: Text(l10n.agentActionsPreflightSettingsClearedMessage),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
    widget.provider.notifyListeners();
  }
}
