import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// Controlled disclosure keeps sections open when validation targets a field.
class AgentActionEditorSection extends StatelessWidget {
  const AgentActionEditorSection({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.summary,
    super.key,
  });

  final String title;
  final String? summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: Button(
              onPressed: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: context.bodyStrong),
                          if (summary != null) Text(summary!, style: context.captionText),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down, size: 12),
                  ],
                ),
              ),
            ),
          ),
          ExcludeFocus(
            excluding: !expanded,
            child: Offstage(
              offstage: !expanded,
              child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
            ),
          ),
        ],
      ),
    );
  }
}
