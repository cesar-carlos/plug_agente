import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_form_state.dart';

class AgentActionTriggerSaveCoordinator {
  const AgentActionTriggerSaveCoordinator({
    required this.formState,
    required this.provider,
    required this.l10n,
    required this.actionId,
    this.existing,
  });

  final AgentActionTriggerSaveFormState formState;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String actionId;
  final AgentActionTrigger? existing;

  Future<bool> save() async {
    final built = formState.buildTrigger(
      l10n: l10n,
      actionId: actionId,
      existing: existing,
    );
    if (built.trigger == null) {
      return false;
    }

    return provider.saveTrigger(built.trigger!);
  }
}
