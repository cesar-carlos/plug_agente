import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
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
