import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

void main() {
  group('MetricsCollector', () {
    late MetricsCollector collector;

    setUp(() {
      collector = MetricsCollector.instance;
      collector.clear();
    });

    tearDown(() {
      collector.clear();
    });

    group('recordSuccess', () {
      test('should record successful metric', () {
        // Act
        collector.recordSuccess(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 10,
          columnCount: 5,
        );

        // Assert
        expect(collector.count, 1);
        expect(collector.metrics.length, 1);

        final metric = collector.metrics.first;
        expect(metric.queryId, 'query-1');
        expect(metric.query, 'SELECT * FROM users');
        expect(metric.executionDuration.inMilliseconds, 100);
        expect(metric.rowsAffected, 10);
        expect(metric.columnCount, 5);
        expect(metric.success, isTrue);
        expect(metric.errorMessage, isNull);
      });

      test('should emit metric on stream', () async {
        // Arrange
        final metrics = <QueryMetrics>[];
        collector.metricsStream.listen(metrics.add);

        // Act
        collector.recordSuccess(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 10,
          columnCount: 5,
        );

        // Wait for stream emission
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(metrics.length, 1);
        expect(metrics.first.success, isTrue);
      });
    });

    group('recordFailure', () {
      test('should record failure metric', () {
        // Act
        collector.recordFailure(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Table not found',
        );

        // Assert
        expect(collector.count, 1);

        final metric = collector.metrics.first;
        expect(metric.queryId, 'query-1');
        expect(metric.success, isFalse);
        expect(metric.errorMessage, 'Table not found');
        expect(metric.rowsAffected, 0);
        expect(metric.columnCount, 0);
      });

      test('should emit failure on stream', () async {
        // Arrange
        final metrics = <QueryMetrics>[];
        collector.metricsStream.listen(metrics.add);

        // Act
        collector.recordFailure(
          queryId: 'query-1',
          query: 'SELECT * FROM users',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Table not found',
        );

        // Wait for stream emission
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(metrics.length, 1);
        expect(metrics.first.success, isFalse);
      });
    });

    group('getSummary', () {
      test('should return empty summary when no metrics', () {
        // Act
        final summary = collector.getSummary();

        // Assert
        expect(summary.totalQueries, 0);
        expect(summary.successfulQueries, 0);
        expect(summary.failedQueries, 0);
        expect(summary.successRate, 0.0);
      });

      test('should calculate summary correctly', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordSuccess(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 200),
          rowsAffected: 2,
          columnCount: 1,
        );
        collector.recordFailure(
          queryId: 'q3',
          query: 'SELECT 3',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Error',
        );

        // Act
        final summary = collector.getSummary();

        // Assert
        expect(summary.totalQueries, 3);
        expect(summary.successfulQueries, 2);
        expect(summary.failedQueries, 1);
        expect(summary.successRate, 66.66666666666666);
        expect(
          summary.averageExecutionTime.inMilliseconds,
          116,
        ); // (100+200+50)/3
        expect(summary.totalRowsAffected, 3); // 1+2+0
      });

      test('should limit summary to recent metrics', () {
        // Arrange
        for (var i = 0; i < 150; i++) {
          collector.recordSuccess(
            queryId: 'q$i',
            query: 'SELECT $i',
            executionDuration: const Duration(milliseconds: 100),
            rowsAffected: 1,
            columnCount: 1,
          );
        }

        // Act
        final summary = collector.getSummary();

        // Assert
        expect(summary.totalQueries, 100); // Limited to 100
      });
    });

    group('getMetrics', () {
      test('should return all metrics when no filter', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordFailure(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Error',
        );

        // Act
        final metrics = collector.getMetrics();

        // Assert
        expect(metrics.length, 2);
      });

      test('should filter by success', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );

        collector.recordFailure(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 50),
          errorMessage: 'Error',
        );

        // Act
        final successMetrics = collector.getMetrics(success: true);
        final failureMetrics = collector.getMetrics(success: false);

        // Assert
        expect(successMetrics.length, 1);
        expect(failureMetrics.length, 1);
        expect(successMetrics.first.success, isTrue);
        expect(failureMetrics.first.success, isFalse);
      });
    });

    group('getSlowQueries', () {
      test('should return queries above threshold', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 500),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordSuccess(
          queryId: 'q2',
          query: 'SELECT 2',
          executionDuration: const Duration(milliseconds: 1500),
          rowsAffected: 1,
          columnCount: 1,
        );
        collector.recordSuccess(
          queryId: 'q3',
          query: 'SELECT 3',
          executionDuration: const Duration(milliseconds: 2000),
          rowsAffected: 1,
          columnCount: 1,
        );

        // Act
        final slowQueries = collector.getSlowQueries();

        // Assert
        expect(slowQueries.length, 2); // 1500ms and 2000ms
        expect(
          slowQueries.first.executionDuration.inMilliseconds,
          2000,
        ); // Sorted desc
      });

      test('should return empty list when no slow queries', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );

        // Act
        final slowQueries = collector.getSlowQueries();

        // Assert
        expect(slowQueries, isEmpty);
      });
    });

    group('clear', () {
      test('should remove all metrics', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 1,
          columnCount: 1,
        );

        // Act
        collector.clear();

        // Assert
        expect(collector.count, 0);
        expect(collector.metrics, isEmpty);
      });
    });

    group('exportToJson', () {
      test('should export metrics as JSON', () {
        // Arrange
        collector.recordSuccess(
          queryId: 'q1',
          query: 'SELECT 1',
          executionDuration: const Duration(milliseconds: 100),
          rowsAffected: 5,
          columnCount: 2,
        );

        // Act
        final json = collector.exportToJson();

        // Assert
        expect(json.length, 1);
        expect(json.first['queryId'], 'q1');
        expect(json.first['query'], 'SELECT 1');
        expect(json.first['executionDurationMs'], 100);
        expect(json.first['rowsAffected'], 5);
        expect(json.first['columnCount'], 2);
        expect(json.first['success'], isTrue);
      });
    });

    group('singleton', () {
      test('should return same instance', () {
        // Act
        final instance1 = MetricsCollector.instance;
        final instance2 = MetricsCollector.instance;

        // Assert
        expect(identical(instance1, instance2), isTrue);
      });
    });
  });
}
