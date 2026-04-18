import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockProtocolNegotiator extends Mock implements ProtocolNegotiator {}

void main() {
  setUpAll(() {
    registerFallbackValue(ProtocolCapabilities.defaultCapabilities());
  });

  late _MockFeatureFlags featureFlags;
  late _MockProtocolNegotiator negotiator;
  late List<({String event, dynamic payload})> emitted;
  late int reconnectCalls;

  ProtocolConfig binaryProtocol() => const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
        negotiatedExtensions: {
          'binaryPayload': true,
          'transportFrame': 'payload-frame/1.0',
        },
      );

  setUp(() {
    featureFlags = _MockFeatureFlags();
    negotiator = _MockProtocolNegotiator();
    emitted = <({String event, dynamic payload})>[];
    reconnectCalls = 0;

    when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
    when(() => featureFlags.enableBinaryPayload).thenReturn(true);
  });

  CapabilitiesNegotiator buildNegotiator({
    dynamic Function(dynamic, {String? sourceEvent})? decode,
  }) {
    return CapabilitiesNegotiator(
      negotiator: negotiator,
      featureFlags: featureFlags,
      contractValidator: const RpcContractValidator(),
      localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
      agentIdProvider: () => 'agent-1',
      emit: (event, payload) async {
        emitted.add((event: event, payload: payload));
      },
      decodeIncoming: decode ?? (payload, {String? sourceEvent}) => payload,
      onTimeoutReconnect: () => reconnectCalls++,
    );
  }

  group('sendRegisterAndStartTimeout', () {
    test('emits agent:register frame with capabilities envelope', () async {
      final neg = buildNegotiator();

      await neg.sendRegisterAndStartTimeout();

      expect(emitted, hasLength(1));
      expect(emitted.single.event, 'agent:register');
      final payload = emitted.single.payload as Map<String, dynamic>;
      expect(payload['agentId'], 'agent-1');
      expect(payload['capabilities'], isA<Map<String, dynamic>>());
    });
  });

  group('handleEnvelope - success', () {
    test('returns success outcome and stores wasPostReconnect=false on first run', () {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(binaryProtocol());

      final neg = buildNegotiator();
      final caps = ProtocolCapabilities.defaultCapabilities();
      final outcome = neg.handleEnvelope({'capabilities': caps.toJson()});

      expect(outcome, isA<CapabilitiesNegotiationSuccess>());
      final success = outcome as CapabilitiesNegotiationSuccess;
      expect(success.wasPostReconnect, isFalse);
      expect(neg.hasReceivedCapabilities, isTrue);
    });

    test('marks wasPostReconnect=true after sendReRegisterAfterReconnect', () async {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(binaryProtocol());

      final neg = buildNegotiator();
      await neg.sendReRegisterAfterReconnect();
      final caps = ProtocolCapabilities.defaultCapabilities();
      final outcome = neg.handleEnvelope({'capabilities': caps.toJson()});

      expect(outcome, isA<CapabilitiesNegotiationSuccess>());
      expect((outcome as CapabilitiesNegotiationSuccess).wasPostReconnect, isTrue);
    });
  });

  group('handleEnvelope - failure', () {
    test('returns failure outcome when negotiated protocol violates contract', () {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
      ));

      final neg = buildNegotiator();
      final outcome = neg.handleEnvelope({
        'capabilities': ProtocolCapabilities.defaultCapabilities(
          binaryPayload: false,
          compressions: const ['none'],
        ).toJson(),
      });

      expect(outcome, isA<CapabilitiesNegotiationFailure>());
      expect(neg.hasReceivedCapabilities, isFalse);
    });

    test('returns failure when payload is not a Map', () {
      final neg = buildNegotiator();
      final outcome = neg.handleEnvelope('not a map');

      expect(outcome, isA<CapabilitiesNegotiationFailure>());
    });
  });

  group('reset', () {
    test('clears hasReceivedCapabilities flag', () {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(binaryProtocol());

      final neg = buildNegotiator();
      final caps = ProtocolCapabilities.defaultCapabilities();
      neg.handleEnvelope({'capabilities': caps.toJson()});
      expect(neg.hasReceivedCapabilities, isTrue);

      neg.reset();
      expect(neg.hasReceivedCapabilities, isFalse);
    });
  });
}
