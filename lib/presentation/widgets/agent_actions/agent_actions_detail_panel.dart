import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsDetailPanel extends StatelessWidget {
  const AgentActionsDetailPanel({
    required this.emptySelectionContent,
    required this.selectionContent,
    required this.historyTitle,
    required this.historyFilters,
    required this.historyList,
    required this.detailScrollKey,
    required this.historyListKey,
    super.key,
  });

  static const double compactViewportHeight = 760;

  final Widget emptySelectionContent;
  final Widget selectionContent;
  final Widget historyTitle;
  final Widget historyFilters;
  final Widget historyList;
  final Key detailScrollKey;
  final Key historyListKey;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactLayout = constraints.maxHeight < compactViewportHeight;

          if (compactLayout) {
            return ListView(
              key: detailScrollKey,
              children: [
                selectionContent,
                const SizedBox(height: AppSpacing.lg),
                historyTitle,
                const SizedBox(height: AppSpacing.sm),
                historyFilters,
                const SizedBox(height: AppSpacing.sm),
                KeyedSubtree(
                  key: historyListKey,
                  child: historyList,
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: detailScrollKey,
                  child: selectionContent,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              historyTitle,
              const SizedBox(height: AppSpacing.sm),
              historyFilters,
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: KeyedSubtree(
                  key: historyListKey,
                  child: historyList,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AgentActionsEmptySelectionPanel extends StatelessWidget {
  const AgentActionsEmptySelectionPanel({
    required this.detailScrollKey,
    required this.content,
    super.key,
  });

  final Key detailScrollKey;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListView(
        key: detailScrollKey,
        children: [
          content,
        ],
      ),
    );
  }
}
