import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/shared/widgets/common/centered_message.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class QueryResultDataGrid extends StatelessWidget {
  const QueryResultDataGrid({
    required this.data,
    super.key,
    this.columnMetadata,
  });
  final List<Map<String, dynamic>> data;
  final List<Map<String, dynamic>>? columnMetadata;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const CenteredMessage(
        title: 'Nenhum resultado',
        message: 'A consulta não retornou dados.',
        icon: FluentIcons.table,
      );
    }

    final columnKeys = data.first.keys.toList();
    final columns = _generateColumns(columnKeys);
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
      final metadata = _findColumnMetadata(key);
      final columnWidth = _calculateColumnWidth(key, metadata);

      return GridColumn(
        columnName: key,
        width: columnWidth,
        label: Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: Text(
            metadata?['name'] as String? ?? key,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }).toList();
  }

  Map<String, dynamic>? _findColumnMetadata(String columnName) {
    if (columnMetadata == null) return null;

    try {
      return columnMetadata!.firstWhere(
        (col) =>
            (col['name'] as String?)?.toLowerCase() == columnName.toLowerCase(),
      );
    } on Exception {
      return null;
    }
  }

  double _calculateColumnWidth(
    String columnName,
    Map<String, dynamic>? metadata,
  ) {
    const minWidth = 80.0;
    const maxWidth = 300.0;
    const padding = 32.0; // Padding para texto + ícones de ordenação/filtro
    const charWidth = 8.0; // Largura aproximada por caractere

    // Calcular largura baseada no nome da coluna
    final columnDisplayName = metadata?['name'] as String? ?? columnName;
    final nameWidth = columnDisplayName.length * charWidth + padding;

    // Calcular largura baseada no tamanho da coluna no banco
    double? sizeWidth;
    if (metadata != null) {
      final length = _extractLength(metadata['length']);
      if (length != null && length > 0) {
        // Para colunas de texto, usar o tamanho como referência
        // Limitar a um máximo razoável (ex: 50 caracteres para cálculo)
        final effectiveLength = length > 50 ? 50 : length;
        sizeWidth = effectiveLength * charWidth + padding;
      }
    }

    // Usar o maior entre nome e tamanho, mas respeitando limites
    var finalWidth = nameWidth;
    if (sizeWidth != null && sizeWidth > finalWidth) {
      finalWidth = sizeWidth;
    }

    // Garantir limites mínimo e máximo
    if (finalWidth < minWidth) {
      finalWidth = minWidth;
    }
    if (finalWidth > maxWidth) {
      finalWidth = maxWidth;
    }

    return finalWidth;
  }

  /// Extrai o valor de length do metadata, suportando String ou int
  int? _extractLength(dynamic lengthValue) {
    if (lengthValue == null) return null;

    if (lengthValue is int) {
      return lengthValue;
    }

    if (lengthValue is String) {
      return int.tryParse(lengthValue);
    }

    // Tentar converter para string e depois para int
    return int.tryParse(lengthValue.toString());
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
          child: Text(
            cell.value?.toString() ?? '',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }
}
