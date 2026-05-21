import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_content_dialog.dart';

class AgentActionDetailsDialog extends StatelessWidget {
  const AgentActionDetailsDialog({
    required this.definition,
    required this.l10n,
    required this.content,
    super.key,
  });

  final AgentActionDefinition definition;
  final AppLocalizations l10n;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return AppContentDialog(
      maxWidth: 980,
      maxHeight: 780,
      contentWidth: 920,
      contentHeight: 660,
      title: Text(definition.name),
      closeTooltip: l10n.btnClose,
      onClose: () => Navigator.pop(context),
      content: content,
    );
  }
}
