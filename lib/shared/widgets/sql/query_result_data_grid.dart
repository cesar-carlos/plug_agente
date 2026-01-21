import 'package:fluent_ui/fluent_ui.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../common/centered_message.dart';

class QueryResultDataGrid extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const QueryResultDataGrid({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const CenteredMessage(
        title: 'Nenhum resultado',
        message: 'A consulta não retornou dados.',
        icon: FluentIcons.table,
      );
    }

    final columns = _generateColumns(data.first.keys.toList());
    final dataSource = _QueryDataSource(data);

    return SfDataGrid(
      source: dataSource,
      columns: columns,
      allowSorting: true,
      allowFiltering: true,
      gridLinesVisibility: GridLinesVisibility.both,
      headerGridLinesVisibility: GridLinesVisibility.both,
      selectionMode: SelectionMode.single,
    );
  }

  List<GridColumn> _generateColumns(List<String> keys) {
    return keys.map((key) {
      return GridColumn(
        columnName: key,
        label: Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }).toList();
  }
}

class _QueryDataSource extends DataGridSource {
  _QueryDataSource(this.data);

  final List<Map<String, dynamic>> data;

  @override
  List<DataGridRow> get rows {
    if (data.isEmpty) return [];
    final keys = data.first.keys.toList();
    return data.map((row) {
      return DataGridRow(
        cells: keys.map((key) {
          return DataGridCell(columnName: key, value: row[key]);
        }).toList(),
      );
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        return Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.centerLeft,
          child: Text(cell.value?.toString() ?? '', overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }
}
