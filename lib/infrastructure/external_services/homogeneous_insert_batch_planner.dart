import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';

/// Detects large homogeneous `INSERT ... VALUES (...)` batches that can be routed
/// to the native ODBC bulk-insert path instead of row-by-row execution.
final class HomogeneousInsertBatchPlanner {
  HomogeneousInsertBatchPlanner._();

  /// Whether homogeneous INSERT batches may auto-route to the native bulk-insert
  /// path for [databaseType].
  ///
  /// SQL Anywhere is excluded until VARCHAR/date/timestamp column mapping in the
  /// bulk-insert executor is validated for that dialect.
  static bool supportsAutoRoute(DatabaseType databaseType) {
    return switch (databaseType) {
      DatabaseType.sqlServer || DatabaseType.postgresql => true,
      DatabaseType.sybaseAnywhere => false,
    };
  }

  static final RegExp _insertShape = RegExp(
    r'^insert\s+into\s+([^\s(]+)\s*\(([^)]+)\)\s*values\s*\((.+)\)\s*$',
  );
  static HomogeneousInsertBatchPlan? tryPlan(
    List<SqlCommand> commands, {
    int? routeThreshold,
  }) {
    final threshold = routeThreshold ?? ConnectionConstants.batchBulkInsertRouteThreshold;
    if (commands.length < threshold) {
      return null;
    }

    String? tableName;
    List<String>? columnNames;
    final rows = <List<dynamic>>[];

    for (final command in commands) {
      if (!NativeCompatibleAcquirePolicy.isTransactionalDml(command.sql)) {
        return null;
      }

      final parsed = _parseInsert(command.sql);
      if (parsed == null) {
        return null;
      }

      tableName ??= parsed.tableName;
      columnNames ??= parsed.columnNames;
      if (tableName != parsed.tableName || !_columnsEqual(columnNames, parsed.columnNames)) {
        return null;
      }
      rows.add(parsed.values);
    }

    if (tableName == null || columnNames == null || rows.isEmpty) {
      return null;
    }

    final columns = List<BulkInsertColumn>.generate(
      columnNames.length,
      (index) => BulkInsertColumn(
        name: columnNames![index],
        type: _inferColumnType(columnNames[index], rows, index),
      ),
      growable: false,
    );

    return HomogeneousInsertBatchPlan(
      request: BulkInsertRequest(
        table: tableName,
        columns: columns,
        rows: rows,
      ),
    );
  }

  static bool shouldRecommend(List<SqlCommand> commands) {
    return tryPlan(
          commands,
          routeThreshold: ConnectionConstants.batchBulkInsertRecommendationThreshold,
        ) !=
        null;
  }

  static _ParsedInsert? _parseInsert(String sql) {
    final normalized = _normalizeInsertSql(sql);
    final match = _insertShape.firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final tableName = match.group(1);
    final rawColumns = match.group(2);
    final rawValues = match.group(3);
    if (tableName == null || rawColumns == null || rawValues == null) {
      return null;
    }

    final columnNames = rawColumns
        .split(',')
        .map((value) => value.trim().replaceAll('"', '').replaceAll('[', '').replaceAll(']', ''))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (columnNames.isEmpty) {
      return null;
    }

    final values = _parseValues(rawValues);
    if (values == null || values.length != columnNames.length) {
      return null;
    }

    return _ParsedInsert(
      tableName: tableName,
      columnNames: columnNames,
      values: values,
    );
  }

  static String _normalizeInsertSql(String sql) {
    return NativeCompatibleAcquirePolicy.normalizeSql(sql);
  }

  static bool _columnsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i].toLowerCase() != right[i].toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  static List<dynamic>? _parseValues(String rawValues) {
    final values = <dynamic>[];
    var index = 0;
    while (index < rawValues.length) {
      while (index < rawValues.length && (rawValues[index] == ' ' || rawValues[index] == ',')) {
        index++;
      }
      if (index >= rawValues.length) {
        break;
      }

      if (rawValues[index] == "'") {
        final parsed = _readQuotedString(rawValues, index);
        if (parsed == null) {
          return null;
        }
        values.add(parsed.value);
        index = parsed.nextIndex;
        continue;
      }

      if (rawValues.startsWith("n'", index)) {
        final parsed = _readQuotedString(rawValues, index + 1);
        if (parsed == null) {
          return null;
        }
        values.add(parsed.value);
        index = parsed.nextIndex;
        continue;
      }

      final end = _readBareTokenEnd(rawValues, index);
      final token = rawValues.substring(index, end).trim();
      if (token.isEmpty) {
        return null;
      }
      final parsedToken = _parseBareToken(token);
      if (parsedToken == _unparsedToken) {
        return null;
      }
      values.add(parsedToken);
      index = end;
    }

    return values;
  }

  static const Object _unparsedToken = Object();

  static _QuotedString? _readQuotedString(String input, int startQuoteIndex) {
    if (input[startQuoteIndex] != "'") {
      return null;
    }
    final buffer = StringBuffer();
    var index = startQuoteIndex + 1;
    while (index < input.length) {
      final char = input[index];
      if (char == "'") {
        if (index + 1 < input.length && input[index + 1] == "'") {
          buffer.write("'");
          index += 2;
          continue;
        }
        return _QuotedString(buffer.toString(), index + 1);
      }
      buffer.write(char);
      index++;
    }
    return null;
  }

  static int _readBareTokenEnd(String input, int start) {
    var index = start;
    while (index < input.length && input[index] != ',') {
      index++;
    }
    return index;
  }

  static Object? _parseBareToken(String token) {
    final lower = token.toLowerCase();
    if (lower == 'null') {
      return null;
    }
    if (lower == 'true') {
      return 1;
    }
    if (lower == 'false') {
      return 0;
    }
    final intValue = int.tryParse(token);
    if (intValue != null) {
      return intValue;
    }
    final doubleValue = double.tryParse(token);
    if (doubleValue != null) {
      return doubleValue;
    }
    return _unparsedToken;
  }

  static BulkInsertColumnType _inferColumnType(
    String columnName,
    List<List<dynamic>> rows,
    int columnIndex,
  ) {
    final normalizedName = columnName.toLowerCase();
    if (normalizedName.startsWith('is_') || normalizedName.endsWith('_flag')) {
      return BulkInsertColumnType.i32;
    }
    if (normalizedName == 'id' || normalizedName.endsWith('_id')) {
      return _rowsFitI32(rows, columnIndex) ? BulkInsertColumnType.i32 : BulkInsertColumnType.i64;
    }
    if (normalizedName.contains('amt') ||
        normalizedName.contains('amount') ||
        normalizedName.contains('price') ||
        normalizedName.contains('total')) {
      return BulkInsertColumnType.decimal;
    }
    if (normalizedName.contains('ts') ||
        normalizedName.endsWith('_at') ||
        normalizedName.contains('timestamp') ||
        normalizedName.contains('datetime')) {
      return BulkInsertColumnType.timestamp;
    }

    var allNullOrInt = true;
    var allNullOrNumeric = true;
    var fitsI32 = true;
    for (final row in rows) {
      final value = row[columnIndex];
      if (value == null) {
        continue;
      }
      if (value is! int) {
        allNullOrInt = false;
      } else if (value < -0x80000000 || value > 0x7fffffff) {
        fitsI32 = false;
      }
      if (value is! int && value is! double) {
        allNullOrNumeric = false;
      }
      if (!allNullOrInt && !allNullOrNumeric) {
        return BulkInsertColumnType.text;
      }
    }
    if (allNullOrInt) return fitsI32 ? BulkInsertColumnType.i32 : BulkInsertColumnType.i64;
    if (allNullOrNumeric) return BulkInsertColumnType.decimal;
    return BulkInsertColumnType.text;
  }

  static bool _rowsFitI32(List<List<dynamic>> rows, int columnIndex) {
    for (final row in rows) {
      final value = row[columnIndex];
      if (value is! int) {
        continue;
      }
      if (value < -0x80000000 || value > 0x7fffffff) {
        return false;
      }
    }
    return true;
  }
}

final class HomogeneousInsertBatchPlan {
  const HomogeneousInsertBatchPlan({
    required this.request,
  });

  final BulkInsertRequest request;
}

final class _ParsedInsert {
  const _ParsedInsert({
    required this.tableName,
    required this.columnNames,
    required this.values,
  });

  final String tableName;
  final List<String> columnNames;
  final List<dynamic> values;
}

final class _QuotedString {
  const _QuotedString(this.value, this.nextIndex);

  final String value;
  final int nextIndex;
}
