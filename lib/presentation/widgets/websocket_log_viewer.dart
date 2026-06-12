import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_tabbed_pane.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class WebSocketLogViewer extends StatelessWidget {
  const WebSocketLogViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = constraints.maxHeight < 50 ? AppSpacing.sm : AppSpacing.md;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.wsLogTitle, style: context.sectionTitle),
              SizedBox(height: spacing),
              Expanded(
                child: WebSocketLogTabbedPane(l10n: l10n),
              ),
            ],
          );
        },
      ),
    );
  }
}
