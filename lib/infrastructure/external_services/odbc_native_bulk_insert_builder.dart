import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';

/// Builds native `BulkInsertBuilder` payloads, preferring columnar `addColumn*`
/// APIs when column types are homogeneous.
final class OdbcNativeBulkInsertBuilder {
  OdbcNativeBulkInsertBuilder._();

  static BulkInsertBuilder fromRequest(BulkInsertRequest request) {
    final columnar = _tryBuildColumnar(request);
    if (columnar != null) {
      return columnar;
    }
    return _buildRowOriented(request);
  }

  static BulkInsertBuilder? _tryBuildColumnar(BulkInsertRequest request) {
    if (request.rows.isEmpty) {
      return null;
    }

    final builder = BulkInsertBuilder()..table(request.table);
    final rowCount = request.rows.length;

    for (var columnIndex = 0; columnIndex < request.columns.length; columnIndex++) {
      final column = request.columns[columnIndex];
      final isNull = List<bool>.generate(
        rowCount,
        (rowIndex) => request.rows[rowIndex][columnIndex] == null,
      );
      final hasNulls = isNull.any((value) => value);
      final nullMask = hasNulls ? isNull : null;

      switch (column.type) {
        case BulkInsertColumnType.i32:
          final values = Int32List(rowCount);
          for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
            final value = request.rows[rowIndex][columnIndex];
            if (value == null) {
              continue;
            }
            final coerced = _coerceInt32Cell(value as Object);
            if (coerced == null) {
              return null;
            }
            values[rowIndex] = coerced;
          }
          builder.addColumnInt32(
            column.name,
            values,
            nullable: column.nullable,
            isNull: nullMask,
          );
        case BulkInsertColumnType.i64:
          final values = Int64List(rowCount);
          for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
            final value = request.rows[rowIndex][columnIndex];
            if (value == null) {
              continue;
            }
            final coerced = _coerceInt64Cell(value as Object);
            if (coerced == null) {
              return null;
            }
            values[rowIndex] = coerced;
          }
          builder.addColumnInt64(
            column.name,
            values,
            nullable: column.nullable,
            isNull: nullMask,
          );
        case BulkInsertColumnType.text:
          final values = List<String>.filled(rowCount, '');
          for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
            final value = request.rows[rowIndex][columnIndex];
            if (value == null) {
              continue;
            }
            final coerced = _coerceTextCell(value as Object);
            if (coerced == null) {
              return null;
            }
            values[rowIndex] = coerced;
          }
          builder.addColumnText(
            column.name,
            values,
            nullable: column.nullable,
            maxLen: column.maxLen,
            isNull: nullMask,
          );
        case BulkInsertColumnType.decimal:
          final values = List<String>.filled(rowCount, '');
          for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
            final value = request.rows[rowIndex][columnIndex];
            if (value == null) {
              continue;
            }
            if (value is num) {
              values[rowIndex] = value.toString();
              continue;
            }
            if (value is! String) {
              return null;
            }
            values[rowIndex] = value;
          }
          builder.addColumnDecimal(
            column.name,
            values,
            nullable: column.nullable,
            maxLen: column.maxLen,
            isNull: nullMask,
          );
        case BulkInsertColumnType.binary:
          final values = List<Uint8List>.filled(rowCount, Uint8List(0));
          for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
            final value = request.rows[rowIndex][columnIndex];
            if (value == null) {
              continue;
            }
            if (value is Uint8List) {
              values[rowIndex] = value;
              continue;
            }
            if (value is! List<int>) {
              return null;
            }
            values[rowIndex] = Uint8List.fromList(value);
          }
          builder.addColumnBinary(
            column.name,
            values,
            nullable: column.nullable,
            maxLen: column.maxLen,
            isNull: nullMask,
          );
        case BulkInsertColumnType.timestamp:
          final values = List<Object>.filled(
            rowCount,
            BulkTimestamp.fromDateTime(DateTime.fromMillisecondsSinceEpoch(0)),
          );
          for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
            final value = request.rows[rowIndex][columnIndex];
            if (value == null) {
              continue;
            }
            if (value is BulkTimestamp) {
              values[rowIndex] = value;
              continue;
            }
            if (value is DateTime) {
              values[rowIndex] = BulkTimestamp.fromDateTime(value);
              continue;
            }
            if (value is String) {
              final parsed = DateTime.tryParse(value);
              if (parsed == null) {
                return null;
              }
              values[rowIndex] = BulkTimestamp.fromDateTime(parsed);
              continue;
            }
            return null;
          }
          builder.addColumnTimestamp(
            column.name,
            values,
            nullable: column.nullable,
            isNull: nullMask,
          );
      }
    }

    return builder;
  }

  static BulkInsertBuilder _buildRowOriented(BulkInsertRequest request) {
    final builder = BulkInsertBuilder()..table(request.table);
    for (final column in request.columns) {
      builder.addColumn(
        column.name,
        _toNativeBulkColumnType(column.type),
        nullable: column.nullable,
        maxLen: column.maxLen,
      );
    }
    for (final row in request.rows) {
      builder.addRow(_coerceBulkInsertRow(row, request.columns));
    }
    return builder;
  }

  static List<dynamic> _coerceBulkInsertRow(
    List<dynamic> row,
    List<BulkInsertColumn> columns,
  ) {
    return List<dynamic>.generate(row.length, (index) {
      final value = row[index];
      final column = columns[index];
      if (value == null || column.type != BulkInsertColumnType.timestamp) {
        return value;
      }
      if (value is BulkTimestamp) {
        return value;
      }
      if (value is DateTime) {
        return BulkTimestamp.fromDateTime(value);
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return BulkTimestamp.fromDateTime(parsed);
        }
      }
      return value;
    });
  }

  static BulkColumnType _toNativeBulkColumnType(BulkInsertColumnType type) {
    return switch (type) {
      BulkInsertColumnType.i32 => BulkColumnType.i32,
      BulkInsertColumnType.i64 => BulkColumnType.i64,
      BulkInsertColumnType.text => BulkColumnType.text,
      BulkInsertColumnType.decimal => BulkColumnType.decimal,
      BulkInsertColumnType.binary => BulkColumnType.binary,
      BulkInsertColumnType.timestamp => BulkColumnType.timestamp,
    };
  }

  static int? _coerceInt32Cell(Object value) {
    if (value is int) {
      return value;
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static int? _coerceInt64Cell(Object value) {
    if (value is int) {
      return value;
    }
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static String? _coerceTextCell(Object value) {
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }
}
