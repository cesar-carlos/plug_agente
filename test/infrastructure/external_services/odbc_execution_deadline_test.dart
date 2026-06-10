import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';

void main() {
  group('OdbcExecutionDeadline', () {
    test('deadlineFor returns null when timeout is null', () {
      expect(OdbcExecutionDeadline.deadlineFor(null), isNull);
    });

    test('deadlineFor returns now plus timeout', () {
      const timeout = Duration(seconds: 30);
      final before = DateTime.now();
      final deadline = OdbcExecutionDeadline.deadlineFor(timeout);
      final after = DateTime.now();

      expect(deadline, isNotNull);
      expect(
        deadline!.difference(before),
        greaterThanOrEqualTo(timeout),
      );
      expect(
        deadline.difference(after),
        lessThanOrEqualTo(timeout),
      );
    });

    test('remainingFromDeadline returns null when deadline is null', () {
      expect(OdbcExecutionDeadline.remainingFromDeadline(null), isNull);
    });

    test('remainingFromDeadline clamps expired deadline to zero', () {
      final deadline = DateTime.now().subtract(const Duration(milliseconds: 1));

      expect(
        OdbcExecutionDeadline.remainingFromDeadline(deadline),
        Duration.zero,
      );
    });

    test('remainingFromDeadline returns positive remaining time', () {
      const remaining = Duration(seconds: 5);
      final deadline = DateTime.now().add(remaining);

      final actual = OdbcExecutionDeadline.remainingFromDeadline(deadline);

      expect(actual, isNotNull);
      expect(actual, lessThanOrEqualTo(remaining));
      expect(actual, greaterThan(remaining - const Duration(seconds: 1)));
    });
  });
}
