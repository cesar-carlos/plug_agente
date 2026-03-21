import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/delivery_guarantee.dart';

void main() {
  group('DeliveryGuarantee', () {
    test('should have bestEffort and atLeastOnce values', () {
      expect(DeliveryGuarantee.values, contains(DeliveryGuarantee.bestEffort));
      expect(DeliveryGuarantee.values, contains(DeliveryGuarantee.atLeastOnce));
      expect(DeliveryGuarantee.values.length, 2);
    });
  });

  group('DeliveryEventType', () {
    test('should have telemetry, requestCritical and responseCritical', () {
      expect(
        DeliveryEventType.values,
        containsAll([
          DeliveryEventType.telemetry,
          DeliveryEventType.requestCritical,
          DeliveryEventType.responseCritical,
        ]),
      );
    });
  });

  group('DeliveryGuaranteeConfig', () {
    test('should have maxResponseRetries of 3', () {
      expect(DeliveryGuaranteeConfig.maxResponseRetries, 3);
    });

    test('should have responseAckTimeout of 10 seconds', () {
      expect(
        DeliveryGuaranteeConfig.responseAckTimeout,
        const Duration(seconds: 10),
      );
    });

    test('should increase ack retry backoff with attempt and cap', () {
      final d0 = DeliveryGuaranteeConfig.responseAckRetryDelayAfterAttempt(0);
      final d1 = DeliveryGuaranteeConfig.responseAckRetryDelayAfterAttempt(1);
      final dLarge = DeliveryGuaranteeConfig.responseAckRetryDelayAfterAttempt(
        99,
      );
      expect(d1 > d0, isTrue);
      expect(dLarge <= const Duration(milliseconds: 4000), isTrue);
      expect(dLarge >= const Duration(milliseconds: 250), isTrue);
    });
  });
}
