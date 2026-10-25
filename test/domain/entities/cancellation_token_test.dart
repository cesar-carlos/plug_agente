import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
    test('notifications support detachment, reset and idempotent cancellation', () async {
      final token = CancellationToken();
      var notifications = 0;
      final subscription = token.cancellations.listen((_) => notifications++);
      token.cancel();
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      token.reset();
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
      await subscription.cancel();
      token.reset();
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
    });

    test('whenCancelled resolves immediately when already cancelled', () async {
      final token = CancellationToken()..cancel();

      await expectLater(token.whenCancelled, completes);
    });

    test('whenCancelled resolves when cancel is called later', () async {
      final token = CancellationToken();
      final waiter = token.whenCancelled;

      token.cancel();

      await expectLater(waiter, completes);
    });
  });
}
