import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_collapsible_sql_block.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_meta_row.dart';

class WebSocketLogSqlInvestigationItem extends StatelessWidget {
  const WebSocketLogSqlInvestigationItem({
    required this.event,
    required this.l10n,
    super.key,
  });

  final SqlInvestigationEvent event;
  final AppLocalizations l10n;

  String _kindLabel() {
    return switch (event.kind) {
      SqlInvestigationKind.authorizationDenied => l10n.wsSqlInvestigationKindAuth,
      SqlInvestigationKind.executionError => l10n.wsSqlInvestigationKindExec,
    };
  }

  String _timeString() {
    final t = event.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final colors = context.appColors;
    final isAuth = event.kind == SqlInvestigationKind.authorizationDenied;
    final chipColor = isAuth ? colors.warning : colors.error;

    return Semantics(
      container: true,
      label: '${_kindLabel()}, ${event.method}',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md - 4),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: chipColor.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Tooltip(
                  message: _kindLabel(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      _kindLabel(),
                      style: context.bodyMuted.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: chipColor,
                      ),
                    ),
                  ),
                ),
                Text(
                  '[${_timeString()}] ${event.method}',
                  style: context.bodyMuted.copyWith(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (event.reason != null && event.reason!.isNotEmpty) ...[
              WebSocketLogMetaRow(label: l10n.wsSqlInvestigationReason, value: event.reason!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.rpcRequestId != null && event.rpcRequestId!.isNotEmpty) ...[
              WebSocketLogMetaRow(label: l10n.wsSqlInvestigationRpcId, value: event.rpcRequestId!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.internalQueryId != null && event.internalQueryId!.isNotEmpty) ...[
              WebSocketLogMetaRow(label: l10n.wsSqlInvestigationInternalId, value: event.internalQueryId!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.clientId != null && event.clientId!.isNotEmpty) ...[
              WebSocketLogMetaRow(label: l10n.wsSqlInvestigationMetaClientId, value: event.clientId!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.resource != null && event.resource!.isNotEmpty) ...[
              WebSocketLogMetaRow(label: l10n.wsSqlInvestigationMetaResource, value: event.resource!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.operation != null && event.operation!.isNotEmpty) ...[
              WebSocketLogMetaRow(label: l10n.wsSqlInvestigationMetaOperation, value: event.operation!),
              const SizedBox(height: AppSpacing.xs),
            ],
            WebSocketLogMetaRow(
              label: l10n.wsSqlInvestigationExecution,
              value: event.executedInDb ? l10n.wsSqlInvestigationExecutedInDb : l10n.wsSqlInvestigationNotExecuted,
            ),
            if (event.errorMessage != null && event.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.wsSqlInvestigationError,
                style: context.bodyMuted.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              WebSocketLogCollapsibleSqlBlock(
                text: event.errorMessage!,
                l10n: l10n,
                color: colors.error,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.wsSqlInvestigationOriginalSql,
              style: context.bodyMuted.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            WebSocketLogCollapsibleSqlBlock(
              text: event.originalSql,
              l10n: l10n,
            ),
            if (event.effectiveSql != null && event.effectiveSql!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.wsSqlInvestigationEffectiveSql,
                style: context.bodyMuted.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              WebSocketLogCollapsibleSqlBlock(
                text: event.effectiveSql!,
                l10n: l10n,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
