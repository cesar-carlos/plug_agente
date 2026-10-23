import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/settings/agent_action_cpu_settings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class AgentActionsCpuSettingsCard extends StatefulWidget {
  const AgentActionsCpuSettingsCard({required this.settings, super.key});
  final AgentActionCpuSettings settings;
  @override
  State<AgentActionsCpuSettingsCard> createState() => _AgentActionsCpuSettingsCardState();
}

class _AgentActionsCpuSettingsCardState extends State<AgentActionsCpuSettingsCard> {
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.agentActionsCpuLimitTitle, style: context.bodyStrong),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.agentActionsCpuLimitHelp),
          const SizedBox(height: AppSpacing.sm),
          ComboBox<int>(
            value: widget.settings.limitPercent,
            items: [
              for (final value in {0, 25, 50, 75, 100, widget.settings.limitPercent})
                ComboBoxItem(value: value, child: Text(value == 0 ? l10n.agentActionsCpuUnlimited : '$value%')),
            ],
            onChanged: _saving ? null : _save,
          ),
          if (_error != null) InfoBar(title: Text(_error!), severity: InfoBarSeverity.error),
        ],
      ),
    );
  }

  Future<void> _save(int? value) async {
    if (value == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.settings.save(value);
    result.fold((_) {}, (failure) {
      if (failure is ActionFailure) failure.log();
      _error = failure is ActionFailure ? failure.message : '$failure';
    });
    if (mounted) setState(() => _saving = false);
  }
}
