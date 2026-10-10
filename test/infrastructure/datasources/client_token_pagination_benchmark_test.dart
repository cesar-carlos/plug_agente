@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show ApplyInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';

import '../../helpers/memory_token_secret_store.dart';
import '../../helpers/token_page_query_recorder.dart';

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
      final recorder = TokenPageQueryRecorder();
      final db = AppDatabase(executor: NativeDatabase.memory().interceptWith(recorder));
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
      for (final sort in ClientTokenSortOption.values) {
        final expectedIds = List.generate(total, (index) => index);
        if (sort == ClientTokenSortOption.clientAsc || sort == ClientTokenSortOption.clientDesc) {
          expectedIds.sort((a, b) {
            final compared = 'client-$a'.compareTo('client-$b');
            return sort == ClientTokenSortOption.clientAsc ? compared : -compared;
          });
        }
        final orderedIds = expectedIds.map((index) => 'id-${index.toString().padLeft(5, '0')}').toList();
        for (final size in [25, 50, 100]) {
          for (final pageNumber in [2, (total / size).ceil()]) {
            final timings = <int>[];
            // Warm SQLite and policy decoding before collecting five samples.
            await repository.listTokenPage(
              query: ClientTokenListQuery(sort: sort, page: pageNumber, pageSize: size),
            );
            for (var sample = 0; sample < 5; sample++) {
              source.mappedRows = 0;
              final timer = Stopwatch()..start();
              final page = (await repository.listTokenPage(
                query: ClientTokenListQuery(sort: sort, page: pageNumber, pageSize: size),
              )).getOrThrow();
              timer.stop();
              timings.add(timer.elapsedMicroseconds);
              expect(page.items, hasLength(size));
              expect(page.totalCount, total);
              expect(page.page, pageNumber);
              expect(page.items.map((token) => token.id), orderedIds.skip((pageNumber - 1) * size).take(size));
              expect(source.mappedRows, size);
              expect(page.items.every((token) => token.tokenValue == null), isTrue);
              expect(secrets.reads, 0);
            }
            timings.sort();
            final plan = await recorder.explainPageQuery(db.executor);
            expect(plan.join(' '), isNot(contains('TEMP B-TREE')));
            final measurement = <String, Object>{
              'tokens': total,
              'sort': sort.name,
              'pageSize': size,
              'page': pageNumber,
              'queryPlan': plan,
              'mappedRows': source.mappedRows,
              'secretReads': secrets.reads,
              'medianMicroseconds': timings[2],
              'samplesMicroseconds': timings,
            };
            measurements.add(measurement);
            // ignore: avoid_print
            print(jsonEncode(measurement));
          }
        }
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

  for (final total in [1000, 10000]) {
    test('consolidated indexes measure bulk-write and storage costs with $total tokens', () async {
      final previousRecorder = TokenPageQueryRecorder();
      final currentRecorder = TokenPageQueryRecorder();
      final previous = AppDatabase(executor: NativeDatabase.memory().interceptWith(previousRecorder));
      final current = AppDatabase(executor: NativeDatabase.memory().interceptWith(currentRecorder));
      addTearDown(previous.close);
      addTearDown(current.close);
      await previous.getAllConfigs();
      await current.getAllConfigs();
      for (final prefix in ['', 'status_']) {
        for (final direction in ['asc', 'desc']) {
          await previous.customStatement('DROP INDEX idx_client_token_${prefix}client_lower_id_$direction');
        }
      }
      await previous.customStatement(
        'CREATE INDEX idx_client_token_client_created ON client_token_cache_table(client_id, created_at DESC)',
      );
      await previous.customStatement(
        'CREATE INDEX idx_client_token_status_created ON client_token_cache_table(is_revoked, created_at DESC)',
      );
      final rows = List.generate(
        total,
        (index) => ClientTokenCacheTableCompanion.insert(
          id: 'id-$index',
          clientId: 'client-$index',
          tokenHash: Value('hash-$index'),
          createdAt: DateTime.utc(2026),
          syncedAt: DateTime.utc(2026),
          isRevoked: Value(index.isOdd),
          payloadJson: Value(jsonEncode({'database': 'benchmark', 'metadata': List.filled(20, 'value')})),
        ),
      );
      final samples = {previous: <int>[], current: <int>[]};
      // Alternate execution order to reduce warm-up and scheduling bias.
      for (var repeat = 0; repeat < 10; repeat++) {
        for (final db in repeat.isEven ? [previous, current] : [current, previous]) {
          await db.delete(db.clientTokenCacheTable).go();
          final timer = Stopwatch()..start();
          await db.batch((batch) => batch.insertAll(db.clientTokenCacheTable, rows));
          timer.stop();
          if (repeat >= 3) samples[db]!.add(timer.elapsedMicroseconds);
        }
      }

      for (final sort in [ClientTokenSortOption.clientAsc, ClientTokenSortOption.clientDesc]) {
        for (final status in ClientTokenStatusFilter.values) {
          final count = status == ClientTokenStatusFilter.all ? total : total ~/ 2;
          final query = ClientTokenListQuery(sort: sort, status: status, page: count ~/ 50, pageSize: 50);
          final readSamples = {previous: <int>[], current: <int>[]};
          List<String>? expectedIds;
          for (var repeat = 0; repeat < 12; repeat++) {
            for (final db in repeat.isEven ? [previous, current] : [current, previous]) {
              final source = _MeasuredDataSource(db);
              final timer = Stopwatch()..start();
              final page = await source.listTokenPage(query: query);
              timer.stop();
              final ids = page.items.map((token) => token.id).toList();
              expectedIds ??= ids;
              expect(ids, expectedIds);
              expect(page.totalCount, count);
              expect(source.mappedRows, 50);
              if (repeat >= 3) readSamples[db]!.add(timer.elapsedMicroseconds);
            }
          }
          for (final db in [previous, current]) {
            final timings = readSamples[db]!..sort();
            final recorder = identical(db, previous) ? previousRecorder : currentRecorder;
            final plan = await recorder.explainPageQuery(db.executor);
            expect(plan.join(' ').contains('TEMP B-TREE'), identical(db, previous));
            final measurement = <String, Object>{
              'tokens': total,
              'comparisonReadStage': identical(db, previous) ? 'previous' : 'consolidated',
              'sort': sort.name,
              'status': status.name,
              'page': query.page!,
              'pageSize': 50,
              'medianMicroseconds': timings[timings.length ~/ 2],
              'samplesMicroseconds': timings,
              'queryPlan': plan,
            };
            measurements.add(measurement);
            // ignore: avoid_print
            print(jsonEncode(measurement));
          }
        }
      }

      for (final db in [previous, current]) {
        final source = ClientTokenLocalDataSource(db);
        expect(await source.countActiveTokens(), total ~/ 2);
        expect(
          (await source.listTokenPage(query: const ClientTokenListQuery(page: 1, pageSize: 50))).totalCount,
          total,
        );
        final pageCount = (await db.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
        final freePages = (await db.customSelect('PRAGMA freelist_count').getSingle()).read<int>('freelist_count');
        final pageSize = (await db.customSelect('PRAGMA page_size').getSingle()).read<int>('page_size');
        final timings = samples[db]!..sort();
        final measurement = <String, Object>{
          'tokens': total,
          'bulkWriteStage': identical(db, previous) ? 'previous' : 'consolidated',
          'medianMicroseconds': timings[timings.length ~/ 2],
          'samplesMicroseconds': timings,
          'allocatedBytes': (pageCount - freePages) * pageSize,
        };
        measurements.add(measurement);
        // ignore: avoid_print
        print(jsonEncode(measurement));
      }
    });
  }

  tearDownAll(() async {
    final output = File('build/client-token-pagination-benchmark.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(const JsonEncoder.withIndent('  ').convert(measurements));
  });
}
