import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_page_editor.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

/// Defers mounting [AgentActionEditor] until after the first frame so dialog layout settles.
class DeferredAgentActionEditor extends StatefulWidget {
  const DeferredAgentActionEditor({
    required this.provider,
    required this.l10n,
    required this.onSaved,
    this.definition,
    this.dirtyNotifier,
    super.key,
  });

  final AgentActionsProvider provider;
  final AgentActionDefinition? definition;
  final AppLocalizations l10n;
  final VoidCallback onSaved;
  final ValueNotifier<bool>? dirtyNotifier;

  @override
  State<DeferredAgentActionEditor> createState() => _DeferredAgentActionEditorState();
}

class _DeferredAgentActionEditorState extends State<DeferredAgentActionEditor> {
  bool _showEditor = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showEditor = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showEditor) {
      return const Center(child: ProgressRing());
    }

    return AgentActionEditor(
      provider: widget.provider,
      definition: widget.definition,
      l10n: widget.l10n,
      showChrome: false,
      onSaved: widget.onSaved,
      dirtyNotifier: widget.dirtyNotifier,
    );
  }
}
