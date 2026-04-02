import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

/// Defines a column for [AppDataGrid].
class AppGridColumn {
  const AppGridColumn({
    required this.label,
    this.flex = 1,
    this.alignment = Alignment.centerLeft,
  });

  final String label;
  final int flex;
  final AlignmentGeometry alignment;
}

/// Generic, reusable data grid with a styled header and alternating-row body.
///
/// Usage:
/// ```dart
/// AppDataGrid<MyItem>(
///   columns: const [
///     AppGridColumn(label: 'Name', flex: 3),
///     AppGridColumn(label: 'Status', flex: 2),
///     AppGridColumn(label: 'Actions', flex: 2),
///   ],
///   rows: items,
///   rowCells: (item) => [
///     Text(item.name),
///     Text(item.status),
///     _ActionsWidget(item: item),
///   ],
/// )
/// ```
class AppDataGrid<T> extends StatelessWidget {
  const AppDataGrid({
    required this.columns,
    required this.rows,
    required this.rowCells,
    super.key,
    this.scrollController,
    this.emptyMessage,
    this.rowHeight,
  });

  final List<AppGridColumn> columns;
  final List<T> rows;

  /// Returns one widget per column cell for each row.
  final List<Widget> Function(T item) rowCells;

  final ScrollController? scrollController;
  final String? emptyMessage;

  /// Optional fixed row height. Defaults to `null` (intrinsic).
  final double? rowHeight;

  @override
  Widget build(BuildContext context) {
    final strokeColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: strokeColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _AppDataGridHeader(columns: columns, strokeColor: strokeColor),
          if (rows.isEmpty && emptyMessage != null)
            _AppDataGridEmpty(message: emptyMessage!)
          else
            ...List<Widget>.generate(rows.length, (index) {
              return _AppDataGridRow<T>(
                item: rows[index],
                columns: columns,
                cells: rowCells(rows[index]),
                index: index,
                strokeColor: strokeColor,
                height: rowHeight,
                isLast: index == rows.length - 1,
              );
            }),
        ],
      ),
    );
  }
}

/// Scrollable variant of [AppDataGrid].
///
/// The parent must provide a bounded height (e.g. via [SizedBox] or
/// [Expanded]) — this widget fills the available space.
class AppDataGridScrollable<T> extends StatelessWidget {
  const AppDataGridScrollable({
    required this.columns,
    required this.rows,
    required this.rowCells,
    super.key,
    this.scrollController,
    this.emptyMessage,
  });

  final List<AppGridColumn> columns;
  final List<T> rows;
  final List<Widget> Function(T item) rowCells;
  final ScrollController? scrollController;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final strokeColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: strokeColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _AppDataGridHeader(columns: columns, strokeColor: strokeColor),
          if (rows.isEmpty && emptyMessage != null)
            _AppDataGridEmpty(message: emptyMessage!)
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  return _AppDataGridRow<T>(
                    item: rows[index],
                    columns: columns,
                    cells: rowCells(rows[index]),
                    index: index,
                    strokeColor: strokeColor,
                    isLast: index == rows.length - 1,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AppDataGridHeader extends StatelessWidget {
  const _AppDataGridHeader({
    required this.columns,
    required this.strokeColor,
  });

  final List<AppGridColumn> columns;
  final Color strokeColor;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        border: Border(bottom: BorderSide(color: strokeColor)),
      ),
      child: Row(
        children: columns
            .map(
              (col) => Expanded(
                flex: col.flex,
                child: Align(
                  alignment: col.alignment,
                  child: Text(
                    col.label,
                    style: context.bodyStrong,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AppDataGridRow<T> extends StatelessWidget {
  const _AppDataGridRow({
    required this.item,
    required this.columns,
    required this.cells,
    required this.index,
    required this.strokeColor,
    required this.isLast,
    this.height,
  });

  final T item;
  final List<AppGridColumn> columns;
  final List<Widget> cells;
  final int index;
  final Color strokeColor;
  final bool isLast;
  final double? height;

  @override
  Widget build(BuildContext context) {
    assert(
      cells.length == columns.length,
      'rowCells must return exactly ${columns.length} widgets, '
      'got ${cells.length}.',
    );

    final rowColor = index.isEven ? Colors.transparent : FluentTheme.of(context).resources.subtleFillColorSecondary;

    final content = Row(
      children: List<Widget>.generate(
        columns.length,
        (i) => Expanded(
          flex: columns[i].flex,
          child: Align(
            alignment: columns[i].alignment,
            child: cells[i],
          ),
        ),
      ),
    );

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: rowColor,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: strokeColor.withValues(alpha: 0.4),
                ),
              ),
      ),
      child: content,
    );
  }
}

class _AppDataGridEmpty extends StatelessWidget {
  const _AppDataGridEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(child: Text(message)),
    );
  }
}
