import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/centered_message.dart';
import 'package:plug_agente/shared/widgets/sql/query_result_column_type.dart';
import 'package:plug_agente/shared/widgets/sql/sql_visual_identity.dart';
import 'package:pluto_grid/pluto_grid.dart';

/// Above this row count, sorting/filtering are disabled to avoid main-thread spikes.
const int kQueryResultHeavyRowThreshold = 10000;
const double _columnControlsWidth = 40;

double _scaledGridExtent(BuildContext context, double base) {
  final scaler = MediaQuery.textScalerOf(context);
  final factor = (scaler.scale(base) / base).clamp(1.0, 1.45);
  return base * factor;
}

class QueryResultDataGrid extends StatefulWidget {
  const QueryResultDataGrid({
    required this.data,
    super.key,
    this.columnMetadata,
    this.dataRevision = 0,
  });

  final List<Map<String, dynamic>> data;
  final List<Map<String, dynamic>>? columnMetadata;
  final int dataRevision;

  @override
  State<QueryResultDataGrid> createState() => _QueryResultDataGridState();
}

class _QueryResultDataGridState extends State<QueryResultDataGrid> {
  List<PlutoColumn> _columns = [];
  List<PlutoRow> _rows = [];
  PlutoGridStateManager? _stateManager;
  int _generation = 0;

  bool get _isHeavyDataset => widget.data.length > kQueryResultHeavyRowThreshold;

  @override
  void initState() {
    super.initState();
    _updateResults();
  }

  @override
  void didUpdateWidget(QueryResultDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data) ||
        oldWidget.dataRevision != widget.dataRevision ||
        !identical(oldWidget.columnMetadata, widget.columnMetadata)) {
      _updateResults(metadataChanged: !identical(oldWidget.columnMetadata, widget.columnMetadata));
    }
  }

  void _updateResults({bool metadataChanged = false}) {
    final keys = widget.data.isEmpty ? <String>[] : widget.data.first.keys.toList();
    final reuseGrid =
        _stateManager != null &&
        !metadataChanged &&
        _columns.isNotEmpty &&
        _columns.first.enableSorting == !_isHeavyDataset &&
        listEquals(keys, _columns.map((column) => column.field).toList());
    if (!reuseGrid) {
      _generation++;
      _stateManager = null;
      _columns = _createColumns(keys);
    }
    _rows = widget.data.map((row) {
      return PlutoRow(
        cells: {
          for (final key in keys) key: PlutoCell(value: row[key]),
        },
      );
    }).toList();
    final manager = _stateManager;
    if (manager != null) {
      manager.removeAllRows(notify: false);
      manager.appendRows(_rows);
      if (manager.hasFilter) manager.setFilterWithFilterRows(manager.filterRows);
      for (final column in _columns) {
        if (column.sort.isAscending) manager.sortAscending(column);
        if (column.sort.isDescending) manager.sortDescending(column);
      }
    }
  }

  List<PlutoColumn> _createColumns(List<String> keys) {
    final metadataByName = _buildColumnMetadataIndex(widget.columnMetadata);
    return keys.map((key) {
      final metadata = metadataByName[key.toLowerCase()];
      return PlutoColumn(
        title: metadata?['name'] as String? ?? key,
        field: key,
        type: const QueryResultColumnType(),
        readOnly: true,
        enableEditingMode: false,
        enableColumnDrag: false,
        enableSorting: !_isHeavyDataset,
        enableFilterMenuItem: !_isHeavyDataset,
        enableHideColumnMenuItem: false,
        enableSetColumnsMenuItem: false,
        width: _calculateColumnWidth(key, metadata),
        titleTextAlign: PlutoColumnTextAlign.center,
        formatter: (value) => value?.toString() ?? '',
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_columns.isEmpty || widget.data.isEmpty) {
      return CenteredMessage(
        title: l10n.queryNoResults,
        message: l10n.queryNoResultsMessage,
        icon: FluentIcons.table,
      );
    }
    final colors = context.appColors;
    final rowHeight = _scaledGridExtent(context, SqlVisualIdentity.queryResultDataGridRowHeight);
    final headerHeight = _scaledGridExtent(context, SqlVisualIdentity.queryResultDataGridHeaderRowHeight);
    final style =
        (colors.brightness == Brightness.dark ? const PlutoGridStyleConfig.dark() : const PlutoGridStyleConfig())
            .copyWith(
              gridBackgroundColor: colors.surfaceCard,
              rowColor: colors.surfaceCard,
              activatedColor: Color.alphaBlend(colors.selectedFill, colors.surfaceCard),
              activatedBorderColor: colors.brand,
              borderColor: colors.border,
              gridBorderColor: colors.border,
              iconColor: colors.textSecondary,
              disabledIconColor: colors.disabled,
              rowHeight: rowHeight,
              columnHeight: headerHeight,
              columnFilterHeight: headerHeight,
              defaultCellPadding: SqlVisualIdentity.queryResultDataGridCellPadding,
              defaultColumnTitlePadding: SqlVisualIdentity.queryResultDataGridHeaderPadding.copyWith(
                right: SqlVisualIdentity.queryResultDataGridHeaderPadding.right + _columnControlsWidth,
              ),
              cellTextStyle: context.bodyText,
              columnTextStyle: context.bodyStrong,
            );
    return material.Theme(
      data: material.ThemeData(
        useMaterial3: false,
        brightness: colors.brightness,
        colorSchemeSeed: colors.brand,
        fontFamily: context.bodyText.fontFamily,
      ),
      child: material.Material(
        color: colors.surfaceCard,
        child: PlutoGrid(
          key: ValueKey(_generation),
          columns: _columns,
          rows: _rows,
          mode: PlutoGridMode.readOnly,
          onLoaded: (event) {
            _stateManager = event.stateManager;
            event.stateManager.setSelectingMode(PlutoGridSelectingMode.none);
            event.stateManager.setShowColumnFilter(!_isHeavyDataset);
          },
          configuration: PlutoGridConfiguration(
            localeText: Localizations.localeOf(context).languageCode == 'pt'
                ? const PlutoGridLocaleText.brazilianPortuguese()
                : const PlutoGridLocaleText(),
            style: style,
          ),
        ),
      ),
    );
  }

  double _calculateColumnWidth(
    String columnName,
    Map<String, dynamic>? metadata,
  ) {
    const minWidth = 80.0;
    const maxWidth = 300.0;
    const padding = 32.0 + _columnControlsWidth;
    const charWidth = 8.0;

    final columnDisplayName = metadata?['name'] as String? ?? columnName;
    final nameWidth = columnDisplayName.length * charWidth + padding;

    double? sizeWidth;
    if (metadata != null) {
      final length = _extractLength(metadata['length']);
      if (length != null && length > 0) {
        final effectiveLength = length > 50 ? 50 : length;
        sizeWidth = effectiveLength * charWidth + padding;
      }
    }

    var finalWidth = nameWidth;
    if (sizeWidth != null && sizeWidth > finalWidth) {
      finalWidth = sizeWidth;
    }

    if (finalWidth < minWidth) {
      finalWidth = minWidth;
    }
    if (finalWidth > maxWidth) {
      finalWidth = maxWidth;
    }

    return finalWidth;
  }

  int? _extractLength(dynamic lengthValue) {
    if (lengthValue == null) return null;

    if (lengthValue is int) {
      return lengthValue;
    }

    if (lengthValue is String) {
      return int.tryParse(lengthValue);
    }

    return int.tryParse(lengthValue.toString());
  }
}

Map<String, Map<String, dynamic>> _buildColumnMetadataIndex(
  List<Map<String, dynamic>>? columnMetadata,
) {
  if (columnMetadata == null || columnMetadata.isEmpty) {
    return {};
  }
  final out = <String, Map<String, dynamic>>{};
  for (final col in columnMetadata) {
    final name = col['name'] as String?;
    if (name == null || name.isEmpty) {
      continue;
    }
    out[name.toLowerCase()] = col;
  }
  return out;
}
