import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';

enum AgentActionTriggerCategory { demand, schedule, application, result }

AgentActionTriggerCategory triggerCategory(AgentActionTriggerType type) => switch (type) {
  AgentActionTriggerType.manual || AgentActionTriggerType.remote => AgentActionTriggerCategory.demand,
  AgentActionTriggerType.appStart || AgentActionTriggerType.appClose => AgentActionTriggerCategory.application,
  AgentActionTriggerType.actionSucceeded || AgentActionTriggerType.actionFailed => AgentActionTriggerCategory.result,
  _ => AgentActionTriggerCategory.schedule,
};

String triggerDescription(AgentActionTriggerType type, AppLocalizations l10n) => switch (type) {
  AgentActionTriggerType.manual => l10n.triggerManualDescription,
  AgentActionTriggerType.remote => l10n.triggerRemoteDescription,
  AgentActionTriggerType.once => l10n.triggerOnceDescription,
  AgentActionTriggerType.interval => l10n.triggerIntervalDescription,
  AgentActionTriggerType.daily => l10n.triggerDailyDescription,
  AgentActionTriggerType.weekly => l10n.triggerWeeklyDescription,
  AgentActionTriggerType.monthly => l10n.triggerMonthlyDescription,
  AgentActionTriggerType.appStart => l10n.triggerStartDescription,
  AgentActionTriggerType.appClose => l10n.triggerCloseDescription,
  AgentActionTriggerType.actionSucceeded => l10n.triggerSuccessDescription,
  AgentActionTriggerType.actionFailed => l10n.triggerFailureDescription,
};

class AgentActionTriggerTypeField extends StatelessWidget {
  const AgentActionTriggerTypeField({
    required this.value,
    required this.supports,
    required this.labelFor,
    required this.onChanged,
    super.key,
  });
  final AgentActionTriggerType value;
  final bool Function(AgentActionTriggerType) supports;
  final String Function(AgentActionTriggerType) labelFor;
  final ValueChanged<AgentActionTriggerType>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final category = triggerCategory(value);
    final labels = {
      AgentActionTriggerCategory.demand: l10n.triggerDemand,
      AgentActionTriggerCategory.schedule: l10n.triggerSchedule,
      AgentActionTriggerCategory.application: l10n.triggerApplication,
      AgentActionTriggerCategory.result: l10n.triggerResult,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdown<AgentActionTriggerCategory>(
          label: l10n.triggerCategory,
          value: category,
          items: [
            for (final group in labels.keys)
              if (group == category ||
                  AgentActionTriggerType.values.any((type) => triggerCategory(type) == group && supports(type)))
                ComboBoxItem(value: group, child: Text(labels[group]!)),
          ],
          onChanged: onChanged == null
              ? null
              : (group) {
                  if (group == null || group == category) return;
                  onChanged!(
                    AgentActionTriggerType.values.firstWhere(
                      (type) => triggerCategory(type) == group && supports(type),
                    ),
                  );
                },
        ),
        const SizedBox(height: 8),
        AppDropdown<AgentActionTriggerType>(
          label: l10n.agentActionsTriggerFieldType,
          value: value,
          items: [
            for (final type in AgentActionTriggerType.values)
              if (triggerCategory(type) == category && (supports(type) || type == value))
                ComboBoxItem(value: type, enabled: supports(type), child: Text(labelFor(type))),
          ],
          onChanged: onChanged == null
              ? null
              : (type) {
                  if (type != null) onChanged!(type);
                },
        ),
        const SizedBox(height: 8),
        Text(triggerDescription(value, l10n)),
      ],
    );
  }
}
