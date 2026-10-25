import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

// Frozen pre-optimization implementation. The helper currently has no runtime
// callers, so this comparison does not imply faster database queries.
List<Map<String, dynamic>>? _baseline(TypedColumnarResult result) {
  final names = result.columns.map((column) => column.name).toList(growable: false);
  if (names.isEmpty) return null;
  return names.map((name) => <String, dynamic>{'name': name}).toList(growable: false);
}

int _measure(TypedColumnarResult fixture, bool baseline) {
  var checksum = 0;
  final timer = Stopwatch()..start();
  for (var iteration = 0; iteration < 5000; iteration++) {
    final output = baseline ? _baseline(fixture)! : buildStreamingColumnMetadata(fixture)!;
    checksum += output.length + (output[iteration % output.length]['name'] as String).length;
  }
  timer.stop();
  if (checksum <= 0) throw StateError('Metadata was not consumed');
  return timer.elapsedMicroseconds;
}

int _median(List<int> values) => (values.toList()..sort())[values.length ~/ 2];

void main() {
  final reports = <Map<String, Object>>[];
  for (final width in [4, 16, 64, 256]) {
    final fixture = TypedColumnarResult(
      rowCount: 0,
      columns: List.generate(
        width,
        (i) => TypedColumnObject<String>(
          name: 'column_$i',
          kind: TypedColumnKind.string,
          values: const [],
        ),
      ),
    );
    if (jsonEncode(_baseline(fixture)) != jsonEncode(buildStreamingColumnMetadata(fixture))) {
      throw StateError('Metadata differs');
    }
    final before = <int>[];
    final after = <int>[];
    for (var sample = -5; sample < 21; sample++) {
      for (final baseline in sample.isEven ? [true, false] : [false, true]) {
        final elapsed = _measure(fixture, baseline);
        if (sample >= 0) (baseline ? before : after).add(elapsed);
      }
    }
    reports.add({
      'columns': width,
      'baseline_us': before,
      'candidate_us': after,
      'baseline_median_us': _median(before),
      'candidate_median_us': _median(after),
      'reduction_percent': 100 * (1 - _median(after) / _median(before)),
    });
  }
  stdout.writeln(
    jsonEncode({
      'dart': Platform.version,
      'scope': 'column metadata only; no database, network or row conversion',
      'warmup': 5,
      'samples': 21,
      'iterations_per_sample': 5000,
      'results': reports,
    }),
  );
}
