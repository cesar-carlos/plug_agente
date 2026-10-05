import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

Future<void> main(List<String> args) async {
  final warmup = args.isEmpty ? 1 : int.parse(args.single);
  if (warmup < 1 || warmup > 100) throw ArgumentError('Warmup must be between 1 and 100');
  final results = <Map<String, Object?>>[];
  for (final count in [1000, 8000, 50000]) {
    final rows = List<List<dynamic>>.generate(
      count,
      (i) => [
        i,
        if (i % 11 == 0) null else 'row-$i',
        Uint8List.fromList([1, 2, 3]),
        DateTime.utc(2026),
      ],
      growable: false,
    );
    for (final cancel in [false, true]) {
      final samples = <Map<String, int>>[];
      for (var repetition = -warmup; repetition < 9; repetition++) {
        var delivered = 0;
        var cancelled = false;
        var firstUs = 0;
        final timer = Stopwatch()..start();
        await emitMappedRowMajorChunks(
          columns: const ['id', 'name', 'payload', 'created'],
          rows: rows,
          fetchSize: 1000,
          isCancelRequested: () => cancelled,
          onChunk: (chunk) async {
            if (delivered == 0) firstUs = timer.elapsedMicroseconds;
            for (final row in chunk) {
              if (row['id'] != delivered++ ||
                  row['payload'] != 'AQID' ||
                  row['created'] != '2026-01-01T00:00:00.000Z') {
                throw StateError('Mapper order or normalization differs');
              }
            }
            cancelled = cancel;
            await Future<void>.delayed(Duration.zero);
          },
        );
        timer.stop();
        if (delivered != (cancel ? 1000 : count)) throw StateError('Unexpected delivered rows');
        if (repetition >= 0) samples.add({'elapsed_us': timer.elapsedMicroseconds, 'first_chunk_us': firstUs});
      }
      results.add({'rows': count, 'cancel_after_first': cancel, 'samples': samples});
    }
  }
  stdout.writeln(
    jsonEncode({
      'benchmark': 'row_major_mapper_v1',
      'warmup': warmup,
      'repeats': 9,
      'rss_peak_bytes': ProcessInfo.maxRss,
      'scenarios': results,
    }),
  );
}
