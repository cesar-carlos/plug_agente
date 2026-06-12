import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/sql_investigation_provider.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_sql_investigation_item.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

class WebSocketLogSqlInvestigationPane extends StatelessWidget {
  const WebSocketLogSqlInvestigationPane({
    required this.l10n,
    required this.sqlProvider,
    super.key,
  });

  final AppLocalizations l10n;
  final SqlInvestigationProvider sqlProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Tooltip(
            message: l10n.wsSqlInvestigationClearTooltip,
            child: AppButton(
              label: l10n.wsSqlInvestigationClear,
              isPrimary: false,
              labelStyle: context.bodyText,
              onPressed: sqlProvider.clearEvents,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: sqlProvider.events.isEmpty
              ? Center(
                  child: Text(
                    l10n.wsSqlInvestigationEmpty,
                    style: context.bodyMuted,
                  ),
                )
              : ListView.builder(
                  itemCount: sqlProvider.events.length,
                  itemBuilder: (BuildContext context, int index) {
                    return WebSocketLogSqlInvestigationItem(
                      event: sqlProvider.events[index],
                      l10n: l10n,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
