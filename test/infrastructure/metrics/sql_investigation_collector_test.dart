import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/infrastructure/metrics/sql_investigation_collector.dart';

void main() {
  group('SqlInvestigationCollector', () {
    test('should keep newest events first and cap length', () {
      final collector = SqlInvestigationCollector(maxEvents: 3);

      collector.recordAuthorizationDenied(
        method: 'sql.execute',
        originalSql: 'SELECT 1',
      );
      collector.recordAuthorizationDenied(
        method: 'sql.execute',
        originalSql: 'SELECT 2',
      );
      collector.recordAuthorizationDenied(
        method: 'sql.execute',
        originalSql: 'SELECT 3',
      );
      collector.recordAuthorizationDenied(
        method: 'sql.execute',
        originalSql: 'SELECT 4',
      );

      check(collector.events.length).equals(3);
      check(collector.events.first.originalSql).equals('SELECT 4');
      check(collector.events.last.originalSql).equals('SELECT 2');

      collector.dispose();
    });

    test('clear should empty events and notify feedRevisionStream', () async {
      final collector = SqlInvestigationCollector(maxEvents: 10);
      collector.recordAuthorizationDenied(method: 'sql.execute', originalSql: 'A');

      var revisionCount = 0;
      final sub = collector.feedRevisionStream.listen((_) => revisionCount++);

      collector.clear();
      await Future<void>.delayed(Duration.zero);

      check(collector.events).isEmpty();
      check(revisionCount).equals(1);

      await sub.cancel();
      collector.dispose();
    });

    test('eventsStream should emit each recorded event', () async {
      final collector = SqlInvestigationCollector(maxEvents: 10);
      final received = <SqlInvestigationEvent>[];
      final sub = collector.eventsStream.listen(received.add);

      collector.recordAuthorizationDenied(method: 'sql.execute', originalSql: 'X');
      await Future<void>.delayed(Duration.zero);

      check(received.length).equals(1);
      check(received.first.kind).equals(SqlInvestigationKind.authorizationDenied);
      check(received.first.originalSql).equals('X');

      await sub.cancel();
      collector.dispose();
    });
  });
}
