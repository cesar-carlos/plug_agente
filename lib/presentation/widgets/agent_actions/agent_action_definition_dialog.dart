import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_content_dialog.dart';

class AgentActionDefinitionDialog extends StatelessWidget {
  const AgentActionDefinitionDialog({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppContentDialog(
      maxWidth: 980,
      maxHeight: 760,
      contentWidth: 920,
      contentHeight: 680,
      closeTooltip: l10n.btnClose,
      title: const SizedBox.shrink(),
      content: child,
    );
  }
}
