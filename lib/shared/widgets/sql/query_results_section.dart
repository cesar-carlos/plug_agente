import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';
import 'package:plug_agente/shared/widgets/common/centered_message.dart';
import 'package:plug_agente/shared/widgets/sql/query_result_data_grid.dart';

class QueryResultsSection extends StatelessWidget {
  const QueryResultsSection({
    required this.results,
    super.key,
    this.isLoading = false,
    this.executionDuration,
    this.affectedRows,
    this.columnMetadata,
  });
  final List<Map<String, dynamic>> results;
  final bool isLoading;
  final Duration? executionDuration;
  final int? affectedRows;
  final List<Map<String, dynamic>>? columnMetadata;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: ProgressRing());
    }

    if (results.isEmpty) {
      return const CenteredMessage(
        title: AppStrings.queryNoResults,
        message: AppStrings.queryNoResultsMessage,
        icon: FluentIcons.table,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: FluentTheme.of(
                  context,
                ).resources.controlStrokeColorDefault,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: QueryResultDataGrid(
                data: results,
                columnMetadata: columnMetadata,
              ),
            ),
          ),
        ),
        _QueryResultsFooter(
          totalRecords: results.length,
          executionDuration: executionDuration,
          affectedRows: affectedRows,
        ),
      ],
    );
  }
}

class _QueryResultsFooter extends StatelessWidget {
  const _QueryResultsFooter({
    required this.totalRecords,
    this.executionDuration,
    this.affectedRows,
  });
  final int totalRecords;
  final Duration? executionDuration;
  final int? affectedRows;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        border: Border(
          top: BorderSide(
            color: theme.resources.controlStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(FluentIcons.table, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${AppStrings.queryTotalRecords}: $totalRecords',
            style: theme.typography.body,
          ),
          if (executionDuration != null) ...[
            const SizedBox(width: AppSpacing.lg),
            const Icon(FluentIcons.clock, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${AppStrings.queryExecutionTime}: ${_formatDuration(executionDuration!)}',
              style: theme.typography.body,
            ),
          ],
          if (affectedRows != null && affectedRows != totalRecords) ...[
            const SizedBox(width: AppSpacing.lg),
            const Icon(FluentIcons.edit, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${AppStrings.queryAffectedRows}: $affectedRows',
              style: theme.typography.body,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inSeconds < 60) {
      final seconds = duration.inSeconds;
      final milliseconds = duration.inMilliseconds % 1000;
      if (milliseconds == 0) {
        return '${seconds}s';
      }
      return '$seconds.${milliseconds.toString().padLeft(3, '0')}s';
    } else {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '${minutes}m ${seconds}s';
    }
  }
}
