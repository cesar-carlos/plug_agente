import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';

Map<String, String> benchmarkDriverMetadata(NativeOdbcConnection native, int connectionId) {
  final raw = native.getConnectionDbmsInfoJson(connectionId);
  if (raw == null) throw StateError('Live driver metadata unavailable');
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final capabilities = data['capabilities'] as Map<String, dynamic>;
  return {
    'dbms_name': data['dbms_name'] as String,
    'dbms_version': data['dbms_version'] as String,
    'driver_name': capabilities['driver_name'] as String,
    'driver_version': capabilities['driver_version'] as String,
  };
}

/// A run owns only this uniquely named table; setup is outside timed sections.
class OdbcBenchmarkFixture {
  OdbcBenchmarkFixture(this.native, this.connectionId)
    : table = 'plug_bench_${pid}_${DateTime.now().microsecondsSinceEpoch}';

  static const rowCount = 8000;
  final NativeOdbcConnection native;
  final int connectionId;
  final String table;
  bool _created = false;

  String get query => 'SELECT id, name FROM $table ORDER BY id';

  Future<void> create() async {
    _execute('CREATE TABLE $table (id INTEGER NOT NULL PRIMARY KEY, name VARCHAR(32) NOT NULL)');
    _created = true;
    for (var start = 1; start <= rowCount; start += 100) {
      final values = [
        for (var id = start; id < start + 100; id++) "SELECT $id, 'benchmark-row-$id'",
      ];
      _execute('INSERT INTO $table (id, name) ${values.join(' UNION ALL ')}');
    }
  }

  void dispose() {
    if (_created) {
      _execute('DROP TABLE $table');
      _created = false;
    }
  }

  void _execute(String sql) {
    final result = native.executeQueryParams(connectionId, sql, const <ParamValue>[]);
    if (result == null) {
      throw StateError('Benchmark fixture operation failed: ${native.getError()}');
    }
  }
}

void validateBenchmarkRows(List<List<dynamic>> rows) {
  if (rows.length != OdbcBenchmarkFixture.rowCount) {
    throw StateError('Expected ${OdbcBenchmarkFixture.rowCount} rows, received ${rows.length}');
  }
  for (var index = 0; index < rows.length; index++) {
    final id = index + 1;
    if (rows[index].length != 2 || rows[index][0] != id || rows[index][1] != 'benchmark-row-$id') {
      throw StateError('Benchmark row $id differs from the deterministic fixture');
    }
  }
}
