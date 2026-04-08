import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/centered_message.dart';
import 'package:plug_agente/shared/widgets/sql/sql_visual_identity.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

/// Above this row count, sorting/filtering are disabled to avoid main-thread spikes.
const int kQueryResultHeavyRowThreshold = 10000;

/// Scales grid row heights with system text scaling (caps extra growth for density).
double _scaledGridExtent(BuildContext context, double base) {
  final scaler = MediaQuery.textScalerOf(context);
  final factor = (scaler.scale(base) / base).clamp(1.0, 1.45);
  return base * factor;
}

/// Result grid with cached [DataGridRow] rows and O(1) column metadata lookup.
class QueryResultDataGrid extends StatefulWidget {
  const QueryResultDataGrid({
    required this.data,
    super.key,
    this.columnMetadata,
  });

  final List<Map<String, dynamic>> data;
  final List<Map<String, dynamic>>? columnMetadata;

  @override
  State<QueryResultDataGrid> createState() => _QueryResultDataGridState();
}

class _QueryResultDataGridState extends State<QueryResultDataGrid> {
  late final _CachingQueryDataSource _dataSource = _CachingQueryDataSource(
    widget.data,
  );
  Map<String, Map<String, dynamic>> _metadataByLowerName = {};

  @override
  void initState() {
    super.initState();
    _metadataByLowerName = _buildColumnMetadataIndex(widget.columnMetadata);
  }

  @override
  void didUpdateWidget(QueryResultDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final metaChanged = !identical(
      oldWidget.columnMetadata,
      widget.columnMetadata,
    );
    if (metaChanged) {
      _metadataByLowerName = _buildColumnMetadataIndex(widget.columnMetadata);
    }
    final dataChanged = !identical(oldWidget.data, widget.data) || oldWidget.data.length != widget.data.length;
    if (dataChanged) {
      _dataSource.updateData(widget.data);
    }
    if (metaChanged && !dataChanged) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.data.isEmpty) {
      return CenteredMessage(
        title: l10n.queryNoResults,
        message: l10n.queryNoResultsMessage,
        icon: FluentIcons.table,
      );
    }

    final columnKeys = widget.data.first.keys.toList();
    final columns = _generateColumns(context, columnKeys);
    final isHeavyDataset = widget.data.length > kQueryResultHeavyRowThreshold;
    final rowHeight = _scaledGridExtent(
      context,
      SqlVisualIdentity.queryResultDataGridRowHeight,
    );
    final headerRowHeight = _scaledGridExtent(
      context,
      SqlVisualIdentity.queryResultDataGridHeaderRowHeight,
    );

    return SfDataGrid(
      source: _dataSource,
      columns: columns,
      rowHeight: rowHeight,
      headerRowHeight: headerRowHeight,
      allowSorting: !isHeavyDataset,
      allowFiltering: !isHeavyDataset,
      gridLinesVisibility: GridLinesVisibility.both,
      headerGridLinesVisibility: GridLinesVisibility.both,
      selectionMode: SelectionMode.single,
    );
  }

  List<GridColumn> _generateColumns(
    BuildContext context,
    List<String> keys,
  ) {
    return keys.map((key) {
      final metadata = _metadataByLowerName[key.toLowerCase()];
      final columnWidth = _calculateColumnWidth(key, metadata);

      return GridColumn(
        columnName: key,
        width: columnWidth,
        label: Container(
          padding: SqlVisualIdentity.queryResultDataGridHeaderPadding,
          alignment: Alignment.center,
          child: Text(
            metadata?['name'] as String? ?? key,
            style: context.bodyStrong.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ),
      );
    }).toList();
  }

  double _calculateColumnWidth(
    String columnName,
    Map<String, dynamic>? metadata,
  ) {
    const minWidth = 80.0;
    const maxWidth = 300.0;
    const padding = 32.0;
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

/// Avoids rebuilding [DataGridRow] lists on every [rows] access (Syncfusion may
/// read [rows] repeatedly).
class _CachingQueryDataSource extends DataGridSource {
  _CachingQueryDataSource(this._data);

  List<Map<String, dynamic>> _data;
  List<DataGridRow>? _rowsCache;
  int _cachedLength = -1;
  String? _structureKey;

  void updateData(List<Map<String, dynamic>> data) {
    _data = data;
    _invalidateCache();
    notifyListeners();
  }

  void _invalidateCache() {
    _rowsCache = null;
    _cachedLength = -1;
    _structureKey = null;
  }

  String? _computeStructureKey() {
    if (_data.isEmpty) {
      return '';
    }
    final keys = _data.first.keys.toList()..sort();
    return '${_data.length}:${keys.join('|')}';
  }

  @override
  List<DataGridRow> get rows {
    if (_data.isEmpty) {
      return [];
    }
    final structureKey = _computeStructureKey();
    if (_rowsCache != null && _cachedLength == _data.length && _structureKey == structureKey) {
      return _rowsCache!;
    }
    final keys = _data.first.keys.toList();
    _structureKey = structureKey;
    _cachedLength = _data.length;
    _rowsCache = _data.map((row) {
      return DataGridRow(
        cells: keys
            .map(
              (key) => DataGridCell(columnName: key, value: row[key]),
            )
            .toList(),
      );
    }).toList();
    return _rowsCache!;
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        return Container(
          padding: SqlVisualIdentity.queryResultDataGridCellPadding,
          alignment: Alignment.centerLeft,
          child: Text(
            cell.value?.toString() ?? '',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }
}
