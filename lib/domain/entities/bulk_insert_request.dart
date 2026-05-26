enum BulkInsertColumnType {
  i32,
  i64,
  text,
  decimal,
  binary,
  timestamp,
}

class BulkInsertColumn {
  const BulkInsertColumn({
    required this.name,
    required this.type,
    this.nullable = false,
    this.maxLen = 0,
  });

  factory BulkInsertColumn.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    if (rawType is! String) {
      throw const FormatException('Bulk insert column type is required');
    }
    final type = BulkInsertColumnType.values.where((t) => t.name == rawType).firstOrNull;
    if (type == null) {
      throw FormatException('Unknown bulk insert column type: $rawType');
    }
    final rawName = json['name'];
    if (rawName is! String) {
      throw const FormatException('Bulk insert column name is required');
    }
    return BulkInsertColumn(
      name: rawName,
      type: type,
      nullable: json['nullable'] as bool? ?? false,
      maxLen: json['max_len'] as int? ?? json['maxLen'] as int? ?? 0,
    );
  }

  final String name;
  final BulkInsertColumnType type;
  final bool nullable;
  final int maxLen;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      if (nullable) 'nullable': nullable,
      if (maxLen > 0) 'max_len': maxLen,
    };
  }
}

class BulkInsertRequest {
  const BulkInsertRequest({
    required this.table,
    required this.columns,
    required this.rows,
  });

  factory BulkInsertRequest.fromJson(Map<String, dynamic> json) {
    final columnsJson = json['columns'];
    final rowsJson = json['rows'];
    if (columnsJson is! List<dynamic>) {
      throw const FormatException('Bulk insert columns must be an array');
    }
    if (rowsJson is! List<dynamic>) {
      throw const FormatException('Bulk insert rows must be an array');
    }
    return BulkInsertRequest(
      table: json['table'] as String,
      columns: columnsJson
          .map((item) => BulkInsertColumn.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      rows: rowsJson.map((row) => (row as List<dynamic>).toList(growable: false)).toList(growable: false),
    );
  }

  final String table;
  final List<BulkInsertColumn> columns;
  final List<List<dynamic>> rows;

  int get rowCount => rows.length;

  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'columns': columns.map((column) => column.toJson()).toList(growable: false),
      'rows': rows,
    };
  }
}
