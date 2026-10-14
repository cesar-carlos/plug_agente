import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_form_state.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class AgentActionTriggerDateTimeField extends StatelessWidget {
  const AgentActionTriggerDateTimeField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.hint,
    this.timeOnly = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? hint;
  final bool timeOnly;

  Future<void> _pick(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final raw = timeOnly
        ? '${AgentActionTriggerSaveFormState.formatDateTimeForField(now).split(' ').first} ${controller.text}'
        : controller.text;
    var selected = AgentActionTriggerSaveFormState.parseLocalDateTime(raw) ?? now;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => ContentDialog(
          title: Text(label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!timeOnly) ...[
                Text(l10n.triggerLocalDates),
                const SizedBox(height: 12),
                DatePicker(
                  selected: selected,
                  onChanged: (date) => setState(() {
                    selected = DateTime(date.year, date.month, date.day, selected.hour, selected.minute);
                  }),
                ),
                const SizedBox(height: 12),
              ],
              TimePicker(
                selected: selected,
                hourFormat: HourFormat.HH,
                onChanged: (time) => setState(() {
                  selected = DateTime(selected.year, selected.month, selected.day, time.hour, time.minute);
                }),
              ),
            ],
          ),
          actions: [
            Button(onPressed: () => Navigator.pop(context), child: Text(l10n.btnCancel)),
            FilledButton(onPressed: () => Navigator.pop(context, selected), child: Text(l10n.triggerApply)),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final formatted = AgentActionTriggerSaveFormState.formatDateTimeForField(picked);
    controller.text = timeOnly ? formatted.split(' ').last.substring(0, 5) : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppTextField(
      controller: controller,
      label: label,
      enabled: enabled,
      hint: hint,
      suffixIcon: Tooltip(
        message: timeOnly ? l10n.triggerPickTime : l10n.triggerPickDateTime,
        child: IconButton(
          icon: Icon(timeOnly ? FluentIcons.clock : FluentIcons.calendar),
          onPressed: enabled ? () => _pick(context) : null,
        ),
      ),
    );
  }
}
