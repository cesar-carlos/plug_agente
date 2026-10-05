import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';

import 'odbc_benchmark_fixture.dart';

/// One process owns one configuration, so RSS peaks do not cross candidates.
Future<void> main(List<String> args) async {
  final count = int.parse(args[0]);
  final fetch = int.parse(args[1]);
  final buffer = int.parse(args[2]);
  if (![1000, 8000, 50000].contains(count) ||
      ![1000, 2000, 4000, 8000].contains(fetch) ||
      ![65536, 262144, 1048576].contains(buffer)) {
    throw ArgumentError('Unsupported qualification configuration');
  }
  final native = NativeOdbcConnection();
  if (!native.initialize()) throw StateError('Native initialization failed');
  final connection = native.connect(Platform.environment['ODBC_TEST_DSN']!);
  if (connection == 0) throw StateError('Native connection failed');
  final driver = benchmarkDriverMetadata(native, connection);
  final table = 'plug_tuning_${pid}_${DateTime.now().microsecondsSinceEpoch}';
  var created = false;
  void execute(String sql) {
    if (native.executeQueryParams(connection, sql, const <ParamValue>[]) == null) {
      throw StateError('Fixture operation failed');
    }
  }

  try {
    execute(
      'CREATE TABLE $table (id INTEGER NOT NULL PRIMARY KEY, name VARCHAR(4096) NULL, payload VARBINARY(256) NULL)',
    );
    created = true;
    final longText = List.filled(128, 'streaming-value-').join();
    for (var start = 1; start <= count; start += 100) {
      final values = <String>[];
      for (var id = start; id < start + 100 && id <= count; id++) {
        final text = id % 11 == 0 ? 'NULL' : "'${id % 10 == 0 ? longText : 'row-$id'}'";
        final binary = id % 13 == 0 ? 'NULL' : '0x0102030405060708';
        values.add('SELECT $id, $text, $binary');
      }
      execute('INSERT INTO $table (id, name, payload) ${values.join(' UNION ALL ')}');
    }
    final samples = <Map<String, Object>>[];
    final sql = 'SELECT id, name, payload FROM $table ORDER BY id';
    for (var repetition = -1; repetition < 9; repetition++) {
      var rows = 0;
      var chunks = 0;
      var firstUs = 0;
      var peakRss = ProcessInfo.currentRss;
      final timer = Stopwatch()..start();
      await for (final chunk in native.streamQueryBatched(connection, sql, fetchSize: fetch, chunkSize: buffer)) {
        if (chunks++ == 0) firstUs = timer.elapsedMicroseconds;
        for (final row in chunk.rows) {
          final id = ++rows;
          final expectedText = id % 11 == 0
              ? null
              : id % 10 == 0
              ? longText
              : 'row-$id';
          if (row[0] != id ||
              row[1] != expectedText ||
              (id % 13 == 0
                  ? row[2] != null
                  : row[2] is! List<int> || (row[2] as List<int>).join(',') != '1,2,3,4,5,6,7,8')) {
            throw StateError('Streaming fixture mismatch at row $id');
          }
        }
        peakRss = max(peakRss, ProcessInfo.maxRss);
      }
      timer.stop();
      if (rows != count) throw StateError('Expected $count rows, received $rows');
      if (repetition >= 0) {
        samples.add({
          'elapsed_us': timer.elapsedMicroseconds,
          'first_chunk_us': firstUs,
          'rows_per_second': count * 1000000 / timer.elapsedMicroseconds,
          'rss_peak_bytes': peakRss,
          'chunks': chunks,
        });
      }
    }
    // Ending the consumer after the first chunk must close the native stream.
    final cancelTimer = Stopwatch()..start();
    await for (final _ in native.streamQueryBatched(connection, sql, fetchSize: fetch, chunkSize: buffer)) {
      break;
    }
    cancelTimer.stop();
    if (native.executeQueryParams(connection, 'SELECT 1', const <ParamValue>[]) == null) {
      throw StateError('Connection unusable after stream close');
    }
    stdout.writeln(
      jsonEncode({
        'benchmark': 'streaming_tuning_v1',
        'driver': driver,
        'rows': count,
        'fetch_size': fetch,
        'buffer_bytes': buffer,
        'warmup': 1,
        'repeats': 9,
        'cancel_and_first_chunk_us': cancelTimer.elapsedMicroseconds,
        'samples': samples,
      }),
    );
  } finally {
    try {
      if (created) execute('DROP TABLE $table');
    } finally {
      native.disconnect(connection);
    }
  }
}
