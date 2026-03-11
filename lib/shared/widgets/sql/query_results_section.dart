import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/shared/widgets/common/feedback/centered_message.dart';
import 'package:plug_agente/shared/widgets/sql/query_result_data_grid.dart';
import 'package:plug_agente/shared/widgets/sql/sql_visual_identity.dart';

class QueryResultsSection extends StatelessWidget {
  const QueryResultsSection({
    required this.results,
    super.key,
    this.isLoading = false,
    this.isStreaming = false,
    this.rowsProcessed = 0,
    this.progress = 0.0,
    this.executionDuration,
    this.affectedRows,
    this.columnMetadata,
    this.error,
    this.onShowErrorDetails,
  });
  final List<Map<String, dynamic>> results;
  final bool isLoading;
  final bool isStreaming;
  final int rowsProcessed;
  final double progress;
  final Duration? executionDuration;
  final int? affectedRows;
  final List<Map<String, dynamic>>? columnMetadata;
  final String? error;
  final VoidCallback? onShowErrorDetails;

  @override
  Widget build(BuildContext context) {
    if (isLoading && !isStreaming) {
      return const Center(child: ProgressRing());
    }

    if (error != null && error!.isNotEmpty) {
      return _QueryErrorState(
        error: error!,
        onShowDetails: onShowErrorDetails,
      );
    }

    if (results.isEmpty && !isLoading) {
      return const CenteredMessage(
        title: AppStrings.queryNoResults,
        message: AppStrings.queryNoResultsMessage,
        icon: FluentIcons.table,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLoading && isStreaming)
          _StreamingProgressBar(
            rowsProcessed: rowsProcessed,
            progress: progress,
          ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: FluentTheme.of(
                  context,
                ).resources.controlStrokeColorDefault,
              ),
              borderRadius: SqlVisualIdentity.panelBorderRadius,
            ),
            child: ClipRRect(
              borderRadius: SqlVisualIdentity.panelBorderRadius,
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

class _StreamingProgressBar extends StatelessWidget {
  const _StreamingProgressBar({
    required this.rowsProcessed,
    required this.progress,
  });
  final int rowsProcessed;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        border: Border(
          bottom: BorderSide(
            color: theme.resources.controlStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        children: [
          const ProgressRing(strokeWidth: 2),
          const SizedBox(width: AppSpacing.md),
          Text(
            '${AppStrings.queryStreamingProgress}: '
            '$rowsProcessed ${AppStrings.queryStreamingRows}',
            style: context.bodyText,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: ProgressBar(value: progress.clamp(0.0, 1.0)),
          ),
        ],
      ),
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
          _ResultMetric(
            icon: FluentIcons.table,
            text: '${AppStrings.queryTotalRecords}: $totalRecords',
            textStyle: context.bodyText,
          ),
          if (executionDuration != null) ...[
            const SizedBox(width: AppSpacing.lg),
            _ResultMetric(
              icon: FluentIcons.clock,
              text:
                  '${AppStrings.queryExecutionTime}: '
                  '${_formatDuration(executionDuration!)}',
              textStyle: context.bodyText,
            ),
          ],
          if (affectedRows != null && affectedRows != totalRecords) ...[
            const SizedBox(width: AppSpacing.lg),
            _ResultMetric(
              icon: FluentIcons.edit,
              text: '${AppStrings.queryAffectedRows}: $affectedRows',
              textStyle: context.bodyText,
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

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    required this.icon,
    required this.text,
    this.textStyle,
  });

  final IconData icon;
  final String text;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: AppSpacing.sm),
        Text(text, style: textStyle),
      ],
    );
  }
}

class _QueryErrorState extends StatelessWidget {
  const _QueryErrorState({
    required this.error,
    this.onShowDetails,
  });
  final String error;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              FluentIcons.error_badge,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.queryErrorTitle,
              style: context.sectionTitle.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.resources.subtleFillColorSecondary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.5),
                ),
              ),
              child: SelectableText(
                error,
                style: context.bodyText,
              ),
            ),
            if (onShowDetails != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onShowDetails,
                child: const Text(AppStrings.queryErrorShowDetails),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
