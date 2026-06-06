import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/homogeneous_insert_batch_planner.dart';

void main() {
  group('HomogeneousInsertBatchPlanner', () {
    test('returns null below route threshold', () {
      final commands = List<SqlCommand>.generate(
        10,
        (index) => SqlCommand(sql: 'INSERT INTO customers (id) VALUES ($index)'),
      );

      expect(HomogeneousInsertBatchPlanner.tryPlan(commands), isNull);
    });

    test('builds bulk insert plan for homogeneous INSERT batches', () {
      final commands = List<SqlCommand>.generate(
        50,
        (index) => SqlCommand(sql: "INSERT INTO customers (id, code) VALUES ($index, 'c$index')"),
      );

      final plan = HomogeneousInsertBatchPlanner.tryPlan(commands);
      expect(plan, isNotNull);
      expect(plan!.request.table, 'customers');
      expect(plan.request.columns, hasLength(2));
      expect(plan.request.rows, hasLength(50));
      expect(plan.request.rows.first, [0, 'c0']);
    });

    test('rejects mixed tables and non-insert commands', () {
      final mixedTables = [
        ...List<SqlCommand>.generate(
          50,
          (index) => SqlCommand(sql: 'INSERT INTO customers (id) VALUES ($index)'),
        ),
        const SqlCommand(sql: 'INSERT INTO orders (id) VALUES (1)'),
      ];
      expect(HomogeneousInsertBatchPlanner.tryPlan(mixedTables), isNull);

      final mixedKinds = [
        ...List<SqlCommand>.generate(
          50,
          (index) => SqlCommand(sql: 'INSERT INTO customers (id) VALUES ($index)'),
        ),
        const SqlCommand(sql: 'UPDATE customers SET id = 2 WHERE id = 1'),
      ];
      expect(HomogeneousInsertBatchPlanner.tryPlan(mixedKinds), isNull);
    });

    test('supportsAutoRoute excludes SQL Anywhere until bulk mapping is fixed', () {
      expect(HomogeneousInsertBatchPlanner.supportsAutoRoute(DatabaseType.sybaseAnywhere), isFalse);
      expect(HomogeneousInsertBatchPlanner.supportsAutoRoute(DatabaseType.sqlServer), isTrue);
      expect(HomogeneousInsertBatchPlanner.supportsAutoRoute(DatabaseType.postgresql), isTrue);
    });

    test('shouldRecommend uses recommendation threshold independently', () {
      final commands = List<SqlCommand>.generate(
        50,
        (index) => SqlCommand(sql: 'INSERT INTO customers (id) VALUES ($index)'),
      );

      expect(HomogeneousInsertBatchPlanner.shouldRecommend(commands), isTrue);
    });
  });
}
