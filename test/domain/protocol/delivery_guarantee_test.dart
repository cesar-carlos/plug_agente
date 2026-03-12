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
  });
}
