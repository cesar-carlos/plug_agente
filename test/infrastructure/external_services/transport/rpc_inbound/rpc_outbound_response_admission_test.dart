import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_outbound_response_admission.dart';

void main() {
  group('RpcOutboundResponseAdmission', () {
    test('rejects new work at capacity and releases only once', () {
      final admission = RpcOutboundResponseAdmission(maxOutstanding: 1);

      final reservation = admission.tryReserve();
      expect(reservation, isNotNull);
      expect(admission.tryReserve(), isNull);
      expect(admission.active, 1);

      reservation!.release();
      reservation.release();
      expect(admission.active, 0);
      expect(admission.tryReserve(), isNotNull);
    });

    test('reset invalidates old reservations without consuming new capacity', () {
      final admission = RpcOutboundResponseAdmission(maxOutstanding: 1);
      final oldReservation = admission.tryReserve()!;

      admission.reset();
      final currentReservation = admission.tryReserve();
      expect(currentReservation, isNotNull);
      oldReservation.release();
      expect(admission.active, 1);

      currentReservation!.release();
      expect(admission.active, 0);
    });
  });
}
