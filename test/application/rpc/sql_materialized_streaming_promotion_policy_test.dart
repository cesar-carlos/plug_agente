import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_materialized_streaming_promotion_policy.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

void main() {
  const policy = SqlMaterializedStreamingPromotionPolicy();

  test('promotes a few wide rows based on real serialized volume', () {
    final rows = List<Map<String, dynamic>>.generate(
      3,
      (_) => <String, dynamic>{'payload': 'x' * 200000},
    );

    expect(
      policy.shouldPromote(
        rows: rows,
        limits: const TransportLimits(
          maxDecodedPayloadBytes: 4 * 1024 * 1024,
        ),
      ),
      isTrue,
    );
  });

  test('does not promote small materialized results', () {
    expect(
      policy.shouldPromote(
        rows: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ],
        limits: const TransportLimits(maxDecodedPayloadBytes: 1024 * 1024),
      ),
      isFalse,
    );
  });
}
