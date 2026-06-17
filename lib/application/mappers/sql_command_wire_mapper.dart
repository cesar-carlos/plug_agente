import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';

/// Maps SQL batch domain types to and from Plug RPC wire payloads.
final class SqlCommandWireMapper {
  const SqlCommandWireMapper();

  SqlCommand fromJson(Map<String, dynamic> json) {
    return SqlCommand(
      sql: json['sql'] as String,
      params: json['params'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson(SqlCommand command) {
    return {
      'sql': command.sql,
      if (command.params != null) 'params': command.params,
    };
  }

  SqlCommandResult resultFromJson(Map<String, dynamic> json) {
    return SqlCommandResult(
      index: json['index'] as int,
      ok: json['ok'] as bool,
      rows: json['rows'] != null
          ? (json['rows'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList()
          : null,
      rowCount: json['row_count'] as int? ?? json['rowCount'] as int?,
      affectedRows: json['affected_rows'] as int? ?? json['affectedRows'] as int?,
      error: json['error'] as String?,
      columnMetadata: json['column_metadata'] != null
          ? (json['column_metadata'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList()
          : json['columnMetadata'] != null
          ? (json['columnMetadata'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList()
          : null,
    );
  }

  Map<String, dynamic> resultToJson(SqlCommandResult result) {
    final json = <String, dynamic>{
      'index': result.index,
      'ok': result.ok,
      if (result.rows != null) 'rows': result.rows,
      if (result.error != null) 'error': result.error,
      if (result.columnMetadata != null) 'column_metadata': result.columnMetadata,
    };
    RpcWireMap.putOptionalInt(json, 'row_count', result.rowCount);
    RpcWireMap.putOptionalInt(json, 'affected_rows', result.affectedRows);
    return json;
  }

  SqlExecutionOptions optionsFromJson(Map<String, dynamic> json) {
    return SqlExecutionOptions(
      timeoutMs: jsonNonNegativeIntWithDefault(json['timeout_ms'], 30000),
      maxRows: jsonPositiveIntWithDefault(json['max_rows'], 50000),
      transaction: json['transaction'] as bool? ?? false,
      maxParallelReadOnlyBatchItems: jsonPositiveIntWithDefault(
        json['max_parallel_read_only_batch_items'],
        1,
      ),
    );
  }

  Map<String, dynamic> optionsToJson(SqlExecutionOptions options) {
    return {
      'timeout_ms': options.timeoutMs,
      'max_rows': options.maxRows,
      'transaction': options.transaction,
      'max_parallel_read_only_batch_items': options.maxParallelReadOnlyBatchItems,
    };
  }
}
