import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/centered_message.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
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
    this.currentPage = 1,
    this.pageSize = 50,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.showPagination = false,
    this.onPreviousPage,
    this.onNextPage,
    this.onPageSizeChanged,
    this.resultSetCount = 0,
    this.selectedResultSetIndex = 0,
    this.onResultSetChanged,
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
  final int currentPage;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final bool showPagination;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<int>? onPageSizeChanged;
  final int resultSetCount;
  final int selectedResultSetIndex;
  final ValueChanged<int>? onResultSetChanged;

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
      final l10n = AppLocalizations.of(context)!;
      return CenteredMessage(
        title: l10n.queryNoResults,
        message: l10n.queryNoResultsMessage,
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
          currentPage: currentPage,
          pageSize: pageSize,
          hasNextPage: hasNextPage,
          hasPreviousPage: hasPreviousPage,
          showPagination: showPagination,
          onPreviousPage: onPreviousPage,
          onNextPage: onNextPage,
          onPageSizeChanged: onPageSizeChanged,
          resultSetCount: resultSetCount,
          selectedResultSetIndex: selectedResultSetIndex,
          onResultSetChanged: onResultSetChanged,
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
    final l10n = AppLocalizations.of(context)!;

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
            '${l10n.queryStreamingProgress}: '
            '$rowsProcessed ${l10n.queryStreamingRows}',
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
    required this.currentPage,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
    required this.showPagination,
    required this.resultSetCount,
    required this.selectedResultSetIndex,
    this.executionDuration,
    this.affectedRows,
    this.onPreviousPage,
    this.onNextPage,
    this.onPageSizeChanged,
    this.onResultSetChanged,
  });
  final int totalRecords;
  final Duration? executionDuration;
  final int? affectedRows;
  final int currentPage;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final bool showPagination;
  final int resultSetCount;
  final int selectedResultSetIndex;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<int>? onPageSizeChanged;
  final ValueChanged<int>? onResultSetChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final l10n = AppLocalizations.of(context)!;

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
            text: '${l10n.queryPaginationShowing}: $totalRecords',
            textStyle: context.bodyText,
          ),
          if (executionDuration != null) ...[
            const SizedBox(width: AppSpacing.lg),
            _ResultMetric(
              icon: FluentIcons.clock,
              text:
                  '${l10n.queryExecutionTime}: '
                  '${_formatDuration(executionDuration!)}',
              textStyle: context.bodyText,
            ),
          ],
          if (affectedRows != null && affectedRows != totalRecords) ...[
            const SizedBox(width: AppSpacing.lg),
            _ResultMetric(
              icon: FluentIcons.edit,
              text: '${l10n.queryAffectedRows}: $affectedRows',
              textStyle: context.bodyText,
            ),
          ],
          if (resultSetCount > 1) ...[
            const SizedBox(width: AppSpacing.lg),
            _QueryResultSetSelector(
              resultSetCount: resultSetCount,
              selectedResultSetIndex: selectedResultSetIndex,
              onChanged: onResultSetChanged,
            ),
          ],
          const Spacer(),
          if (showPagination)
            _QueryPaginationControls(
              currentPage: currentPage,
              pageSize: pageSize,
              hasNextPage: hasNextPage,
              hasPreviousPage: hasPreviousPage,
              onPreviousPage: onPreviousPage,
              onNextPage: onNextPage,
              onPageSizeChanged: onPageSizeChanged,
            ),
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

class _QueryResultSetSelector extends StatelessWidget {
  const _QueryResultSetSelector({
    required this.resultSetCount,
    required this.selectedResultSetIndex,
    this.onChanged,
  });

  final int resultSetCount;
  final int selectedResultSetIndex;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: 180,
      child: ComboBox<int>(
        value: selectedResultSetIndex,
        placeholder: Text(l10n.queryResultSetLabel),
        items: List<ComboBoxItem<int>>.generate(
          resultSetCount,
          (index) => ComboBoxItem<int>(
            value: index,
            child: Text(
              '${l10n.queryResultSetLabel} ${index + 1}',
            ),
          ),
        ),
        onChanged: (value) {
          if (value != null) {
            onChanged?.call(value);
          }
        },
      ),
    );
  }
}

class _QueryPaginationControls extends StatelessWidget {
  const _QueryPaginationControls({
    required this.currentPage,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
    this.onPreviousPage,
    this.onNextPage,
    this.onPageSizeChanged,
  });

  final int currentPage;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<int>? onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        Text(
          '${l10n.queryPaginationPage} $currentPage',
          style: context.bodyText,
        ),
        SizedBox(
          width: 140,
          child: ComboBox<int>(
            value: pageSize,
            placeholder: Text(l10n.queryPaginationPageSize),
            items: const [25, 50, 100, 250]
                .map(
                  (value) => ComboBoxItem<int>(
                    value: value,
                    child: Text('$value'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onPageSizeChanged?.call(value);
              }
            },
          ),
        ),
        AppButton(
          label: l10n.queryPaginationPrevious,
          isPrimary: false,
          onPressed: hasPreviousPage ? onPreviousPage : null,
        ),
        AppButton(
          label: l10n.queryPaginationNext,
          onPressed: hasNextPage ? onNextPage : null,
        ),
      ],
    );
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
    final l10n = AppLocalizations.of(context)!;
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
              l10n.queryErrorTitle,
              style: context.sectionTitle.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            InlineFeedbackCard(
              severity: InfoBarSeverity.error,
              message: error,
            ),
            if (onShowDetails != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: l10n.queryErrorShowDetails,
                onPressed: onShowDetails,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
