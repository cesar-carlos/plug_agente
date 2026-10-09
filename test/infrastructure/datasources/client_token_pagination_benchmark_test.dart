@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';

import '../../helpers/memory_token_secret_store.dart';

class _MeasuredDataSource extends ClientTokenLocalDataSource {
  _MeasuredDataSource(super._database);
  int mappedRows = 0;

  @override
  ClientTokenSummary mapRowToSummaryWithoutTokenValue(ClientTokenCacheData row) {
    mappedRows++;
    return super.mapRowToSummaryWithoutTokenValue(row);
  }
}

void main() {
  final measurements = <Map<String, Object>>[];
  for (final total in [1000, 10000]) {
    test('pagination bounds decoding and secret access with $total tokens', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final source = _MeasuredDataSource(db);
      final secrets = MemoryTokenSecretStore();
      final repository = ClientTokenRepository(source, secretStore: secrets);
      final payload = jsonEncode({'database': 'benchmark', 'metadata': List.filled(20, 'value')});
      final rules = jsonEncode(
        List.generate(
          10,
          (index) => {
            'resource_type': 'table',
            'resource': 'table_$index',
            'read': true,
            'update': false,
            'delete': false,
            'ddl': false,
            'effect': 'allow',
          },
        ),
      );
      await db.batch((batch) {
        batch.insertAll(
          db.clientTokenCacheTable,
          List.generate(
            total,
            (index) => ClientTokenCacheTableCompanion.insert(
              id: 'id-${index.toString().padLeft(5, '0')}',
              clientId: 'client-$index',
              tokenHash: Value('hash-$index'),
              createdAt: DateTime.utc(2026),
              syncedAt: DateTime.utc(2026),
              payloadJson: Value(payload),
              rulesJson: Value(rules),
            ),
          ),
        );
      });
      for (final size in [25, 50, 100]) {
        final timings = <int>[];
        // Warm SQLite and policy decoding before collecting five samples.
        await repository.listTokenPage(query: ClientTokenListQuery(page: 1, pageSize: size));
        for (var sample = 0; sample < 5; sample++) {
          source.mappedRows = 0;
          final timer = Stopwatch()..start();
          final page = (await repository.listTokenPage(
            query: ClientTokenListQuery(page: 2, pageSize: size),
          )).getOrThrow();
          timer.stop();
          timings.add(timer.elapsedMicroseconds);
          expect(page.items, hasLength(size));
          expect(page.totalCount, total);
          expect(source.mappedRows, size);
          expect(page.items.every((token) => token.tokenValue == null), isTrue);
          expect(secrets.reads, 0);
        }
        timings.sort();
        final measurement = <String, Object>{
          'tokens': total,
          'pageSize': size,
          'mappedRows': source.mappedRows,
          'secretReads': secrets.reads,
          'medianMicroseconds': timings[2],
          'samplesMicroseconds': timings,
        };
        measurements.add(measurement);
        // ignore: avoid_print
        print(jsonEncode(measurement));
      }
      source.mappedRows = 0;
      final timer = Stopwatch()..start();
      expect((await repository.listTokens()).getOrThrow(), hasLength(total));
      timer.stop();
      expect(source.mappedRows, total);
      measurements.add({
        'tokens': total,
        'unpagedMicroseconds': timer.elapsedMicroseconds,
        'mappedRows': source.mappedRows,
        'secretReads': secrets.reads,
      });
    });
  }
  tearDownAll(() async {
    final output = File('build/client-token-pagination-benchmark.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(const JsonEncoder.withIndent('  ').convert(measurements));
  });
}
