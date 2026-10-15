import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_schema.dart';

import '../helpers/source_schema_fixture.dart';

void main() {
  test('measures structural validation CPU with catalog IO replaced', () async {
    final results = <Map<String, Object?>>[];
    for (final width in [16, 128, 1024]) {
      final fixture = SourceSchemaFixture(width);
      results.add(await measure('verify_columns_$width', fixture.validate));
      expect(fixture.catalogCalls, greaterThan(0));
    }
    const key = <String, Object?>{
      'name': 'fk',
      'status': 'enabled',
      'columns': ['a', 'b', 'c', 'd'],
      'targetColumns': ['w', 'x', 'y', 'z'],
      'target': {'schema': 'public', 'name': 'parent', 'type': 'table'},
    };
    final other = {
      ...key,
      'columns': ['a', 'b', 'c', 'd'],
      'targetColumns': ['w', 'x', 'y', 'z'],
    };
    var matches = 0;
    results.add(
      await measure('compare_1000_constraints', () async {
        for (var i = 0; i < 1000; i++) {
          if (OdbcSourceSchema.sameKey(key, other, 'postgres')) matches++;
        }
      }),
    );
    expect(matches, 45000);
    final report = jsonEncode({'benchmark': 'source_schema', 'catalog_io': 'fake', 'samples': 30, 'results': results});
    final output = Platform.environment['SOURCE_SCHEMA_BENCHMARK_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(report);
    // ignore: avoid_print
    print(report);
  }, tags: ['perf']);
}

Future<Map<String, Object?>> measure(String name, Future<void> Function() operation) async {
  for (var i = 0; i < 15; i++) {
    await operation();
  }
  final samples = <int>[];
  for (var i = 0; i < 30; i++) {
    final watch = Stopwatch()..start();
    await operation();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return {'name': name, 'p50_us': samples[15], 'p95_us': samples[28], 'samples_us': samples};
}
