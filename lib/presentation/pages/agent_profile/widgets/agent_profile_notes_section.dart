import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_form_controller.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/agent_profile_section.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class AgentProfileNotesSection extends StatelessWidget {
  const AgentProfileNotesSection({
    required this.controller,
    required this.l10n,
    super.key,
  });

  final AgentProfileFormController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AgentProfileSection(
      title: l10n.agentProfileSectionNotes,
      child: AppTextField(
        label: l10n.agentProfileFieldNotes,
        controller: controller.notesController,
        maxLines: 5,
        textInputAction: TextInputAction.newline,
      ),
    );
  }
}
