// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';

import 'odbc_benchmark_fixture.dart';

Future<void> main(List<String> args) async {
  final dsn = Platform.environment['ODBC_TEST_DSN'] ?? Platform.environment['ODBC_DSN'];
  if (dsn == null || dsn.isEmpty) {
    stderr.writeln('ODBC benchmark requires a DSN');
    exitCode = 2;
    return;
  }
  final native = NativeOdbcConnection();
  if (!native.initialize()) {
    throw StateError('Native environment initialization failed');
  }
  final connection = native.connect(dsn);
  if (connection == 0) {
    throw StateError('Benchmark connection failed');
  }
  final fixture = OdbcBenchmarkFixture(native, connection);
  try {
    final driver = benchmarkDriverMetadata(native, connection);
    await fixture.create();
    final modeIndex = args.indexOf('--mode');
    final mode = modeIndex < 0 ? 'streaming' : args[modeIndex + 1];
    if (mode != 'streaming' && mode != 'async') {
      throw ArgumentError('Expected --mode streaming or async');
    }
    final queryKey = mode == 'streaming' ? 'ODBC_STREAM_BENCH_QUERY' : 'ODBC_BENCH_QUERY';
    final query = Platform.environment[queryKey]?.trim();
    final sql = query == null || query.isEmpty ? fixture.query : query;
    final results = mode == 'streaming' ? await _streaming(native, connection, sql) : await _async(dsn, sql);
    stdout.writeln();
    print(
      jsonEncode({
        'benchmark': 'native_odbc_$mode',
        'harness_version': 2,
        'driver': driver,
        'workload': 'deterministic_8000_rows_v1',
        'rows': OdbcBenchmarkFixture.rowCount,
        'warmup': 1,
        'repeats': 3,
        'scenarios': results,
      }),
    );
  } finally {
    try {
      fixture.dispose();
    } finally {
      native.disconnect(connection);
    }
  }
}

int _positiveEnv(String key, int fallback) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) throw ArgumentError('$key must be positive');
  return parsed;
}

Future<List<Map<String, Object>>> _streaming(NativeOdbcConnection native, int connection, String sql) async {
  final fetch = _positiveEnv('ODBC_STREAM_BENCH_FETCH_SIZE', 1000);
  final buffer = _positiveEnv('ODBC_STREAM_BENCH_CHUNK_SIZE', 1024 * 1024);
  final samples = <String, List<Map<String, Object>>>{'streamQueryBuffer': [], 'streamQueryBatched': []};
  for (var repetition = -1; repetition < 3; repetition++) {
    final labels = repetition.isEven ? samples.keys.toList() : samples.keys.toList().reversed;
    for (final label in labels) {
      final rows = <List<dynamic>>[];
      var chunks = 0;
      final timer = Stopwatch()..start();
      final stream = label == 'streamQueryBuffer'
          ? native.streamQueryBuffer(connection, sql, chunkSize: buffer)
          : native.streamQueryBatched(connection, sql, fetchSize: fetch, chunkSize: buffer);
      await for (final chunk in stream) {
        chunks++;
        rows.addAll(chunk.rows);
      }
      timer.stop();
      validateBenchmarkRows(rows);
      if (repetition >= 0) {
        samples[label]!.add({
          'elapsed_ms': timer.elapsedMicroseconds / 1000,
          'rows': rows.length,
          'chunks': chunks,
          'rows_per_second': rows.length * 1000000 / timer.elapsedMicroseconds,
          'fetch_size': label == 'streamQueryBuffer' ? 0 : fetch,
          'chunk_size': buffer,
        });
      }
    }
  }
  return [
    for (final entry in samples.entries) _aggregate(entry.key, entry.value),
  ];
}

Map<String, Object> _aggregate(String label, List<Map<String, Object>> samples) {
  final sorted = [...samples]..sort((a, b) => (a['elapsed_ms']! as double).compareTo(b['elapsed_ms']! as double));
  return {'scenario': label, ...sorted[sorted.length ~/ 2], 'samples': samples};
}

Future<List<Map<String, Object>>> _async(String dsn, String sql) async {
  final output = <Map<String, Object>>[];
  final queryCount = _positiveEnv('ODBC_BENCH_QUERY_COUNT', 24);
  for (final spec in [
    (label: 'workerCount=1', workers: 1, encoding: ResultEncoding.rowMajor),
    (label: 'workerCount=4', workers: 4, encoding: ResultEncoding.rowMajor),
    (label: 'workerCount=4 columnar', workers: 4, encoding: ResultEncoding.columnar),
    (label: 'workerCount=4 columnar compressed', workers: 4, encoding: ResultEncoding.columnarCompressed),
    (label: 'native pool', workers: 4, encoding: ResultEncoding.rowMajor),
    (label: 'prepared reuse', workers: 1, encoding: ResultEncoding.rowMajor),
  ]) {
    final async = AsyncNativeOdbcConnection(workerCount: spec.workers, maxPendingRequests: queryCount * 8);
    await async.initialize();
    final connections = <int>[];
    var pool = 0;
    var statement = 0;
    try {
      if (spec.label == 'native pool') {
        pool = await async.poolCreate(dsn, 4);
        if (pool == 0) throw StateError('Benchmark pool creation failed');
      } else {
        for (var index = 0; index < 4; index++) {
          final connection = await async.connect(dsn);
          if (connection == 0) throw StateError('Async benchmark connection failed');
          connections.add(connection);
        }
      }
      if (spec.label == 'prepared reuse') {
        statement = await async.prepare(connections.first, sql);
        if (statement == 0) throw StateError('Benchmark prepare failed');
      }
      Future<Uint8List> execute(int index) async {
        final connection = pool != 0 ? await async.poolGetConnection(pool) : connections[index % 4];
        late Uint8List data;
        var returned = true;
        try {
          final result = statement != 0
              ? await async.executePrepared(statement, const <ParamValue>[], 0, 1000)
              : await async.executeQueryParams(connection, sql, const <ParamValue>[], resultEncoding: spec.encoding);
          if (result == null) throw StateError('Async benchmark query failed');
          data = result;
        } finally {
          if (pool != 0) returned = await async.poolReleaseConnection(connection);
        }
        if (!returned) throw StateError('Native pool return failed');
        return data;
      }

      final samples = <Map<String, Object>>[];
      var validationFailed = false;
      for (var repetition = -1; repetition < 3; repetition++) {
        final timer = Stopwatch()..start();
        final results = <Uint8List>[];
        // Four in-flight requests for the pool, and one for prepared reuse.
        final concurrency = statement != 0 ? 1 : (pool != 0 ? 4 : queryCount);
        for (var start = 0; start < queryCount; start += concurrency) {
          results.addAll(
            await Future.wait([
              for (var index = start; index < start + concurrency && index < queryCount; index++) execute(index),
            ]),
          );
        }
        timer.stop();
        if (pool != 0) {
          final state = await async.poolGetState(pool);
          if (state == null || state.size != state.idle) {
            throw StateError('Native pool still reports active connections after all returns');
          }
        }
        for (final data in results) {
          final actual = observedResultEncoding(data);
          if (actual != spec.encoding.name) {
            throw StateError('Requested ${spec.encoding.name}, received $actual');
          }
          if (spec.encoding != ResultEncoding.columnarCompressed) {
            validateBenchmarkRows(BinaryProtocolParser.parse(data).rows);
          }
        }
        if (spec.encoding == ResultEncoding.columnarCompressed) {
          final validator = await Process.start(Platform.resolvedExecutable, [
            'run',
            File.fromUri(Platform.script.resolve('validate_native_odbc_result.dart')).path,
          ]);
          final errors = validator.stderr.transform(utf8.decoder).join();
          final stdoutDone = validator.stdout.drain<void>();
          validator.stdin.write(jsonEncode(results.map(base64Encode).toList()));
          await validator.stdin.close();
          final validatorExit = await validator.exitCode;
          await stdoutDone;
          final details = await errors;
          if (validatorExit != 0) {
            final reproDirectory = Platform.environment['ODBC_BENCH_REPRO_DIR'];
            if (reproDirectory != null) {
              Directory(reproDirectory).createSync(recursive: true);
              File('$reproDirectory/columnar-compressed-input.json').writeAsStringSync(
                jsonEncode(results.map(base64Encode).toList()),
              );
            }
            stderr.writeln('Compressed result decoder subprocess failed ($validatorExit): $details');
            exitCode = 1;
            validationFailed = true;
            output.add({'scenario': spec.label, 'status': 'fail', 'encoding': spec.encoding.name});
            break;
          }
        }
        if (repetition >= 0) {
          final stats = async.getWorkerPoolStats();
          if (stats.timeouts != 0 || stats.fallbacksToBlocking != 0 || stats.failedRequests != 0) {
            throw StateError('Benchmark timed out or fell back to a blocking path');
          }
          samples.add({
            'elapsed_ms': timer.elapsedMicroseconds / 1000,
            'encoding': spec.encoding.name,
            'actual_encoding': spec.encoding.name,
            'workers': spec.workers,
            'query_count': queryCount,
            'max_in_flight': concurrency,
            'pool_size': pool != 0 ? 4 : 0,
            'rows': OdbcBenchmarkFixture.rowCount,
            'queries_per_second': queryCount * 1000000 / timer.elapsedMicroseconds,
            'timeouts': stats.timeouts,
            'fallbacks': stats.fallbacksToBlocking,
            'routed': stats.totalRouted,
            'completed_requests': stats.completedRequests,
            'failed_requests': stats.failedRequests,
          });
        }
      }
      if (!validationFailed) output.add(_aggregate(spec.label, samples));
    } on Object catch (error) {
      stderr.writeln('Native ${spec.label} scenario failed: $error');
      exitCode = 1;
      output.add({'scenario': spec.label, 'status': 'fail', 'encoding': spec.encoding.name});
    } finally {
      if (statement != 0) await async.closeStatement(statement);
      for (final connection in connections) {
        await async.disconnect(connection);
      }
      if (pool != 0) await async.poolClose(pool);
      async.dispose();
    }
  }
  return output;
}

String observedResultEncoding(Uint8List data) {
  if (!BinaryProtocolParser.isColumnarV2Message(data)) return 'rowMajor';
  // Columnar v2 header byte 14 records the global compression policy.
  return data[14] == 0 ? 'columnar' : 'columnarCompressed';
}
