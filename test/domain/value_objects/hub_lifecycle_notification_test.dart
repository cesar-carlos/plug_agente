import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';

void main() {
  group('isHubIoServerInitiatedDisconnect', () {
    test('should return true when reason is io server disconnect', () {
      expect(isHubIoServerInitiatedDisconnect('io server disconnect'), isTrue);
      expect(isHubIoServerInitiatedDisconnect('IO SERVER DISCONNECT'), isTrue);
    });

    test('should return false for transport close and null', () {
      expect(isHubIoServerInitiatedDisconnect('transport close'), isFalse);
      expect(isHubIoServerInitiatedDisconnect(null), isFalse);
    });
  });
}
