import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_batch_negotiation.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/capabilities_negotiator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:result_dart/result_dart.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockProtocolNegotiator extends Mock implements IProtocolNegotiator {}

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
    Result<dynamic> Function(dynamic, {String? sourceEvent})? decode,
    String Function()? agentIdProvider,
    Future<Map<String, dynamic>?> Function()? registerProfileProvider,
  }) {
    return CapabilitiesNegotiator(
      negotiator: negotiator,
      featureFlags: featureFlags,
      contractValidator: const RpcContractValidator(),
      localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
      agentIdProvider: agentIdProvider ?? () => 'agent-1',
      registerProfileProvider: registerProfileProvider,
      emit: (event, payload) async {
        emitted.add((event: event, payload: payload));
        return true;
      },
      decodeIncoming:
          decode ??
          (payload, {String? sourceEvent}) {
            return Success<Object, Exception>(payload as Object) as Result<dynamic>;
          },
      onTimeoutReconnect: () => reconnectCalls++,
    );
  }

  group('sendRegisterAndStartTimeout', () {
    test('emits agent:register frame with capabilities envelope', () async {
      final neg = buildNegotiator();
      addTearDown(neg.reset);

      final sent = await neg.sendRegisterAndStartTimeout();

      expect(sent, isTrue);
      expect(emitted, hasLength(1));
      expect(emitted.single.event, 'agent:register');
      final payload = emitted.single.payload as Map<String, dynamic>;
      expect(payload['agentId'], 'agent-1');
      expect(payload['capabilities'], isA<Map<String, dynamic>>());
      final timestamp = payload['timestamp'] as String;
      expect(timestamp.endsWith('Z'), isTrue);
      expect(DateTime.parse(timestamp).isUtc, isTrue);
    });

    test('includes optional profile sync metadata when provider returns it', () async {
      final neg = buildNegotiator(
        registerProfileProvider: () async => <String, dynamic>{
          'profile': {
            'name': 'Empresa',
            'trade_name': 'Fantasia',
            'document': '52998224725',
            'document_type': 'cpf',
            'mobile': '11988887777',
            'email': 'contato@example.com',
            'address': {
              'street': 'Rua',
              'number': '1',
              'district': 'Centro',
              'postal_code': '01001000',
              'city': 'Sao Paulo',
              'state': 'SP',
            },
          },
          'profile_version': 7,
          'profile_updated_at': '2026-04-08T10:20:00.000Z',
        },
      );
      addTearDown(neg.reset);

      final sent = await neg.sendRegisterAndStartTimeout();

      expect(sent, isTrue);
      final payload = emitted.single.payload as Map<String, dynamic>;
      expect(payload['profile'], isA<Map<String, dynamic>>());
      expect(payload['profile_version'], 7);
      expect(payload['profile_updated_at'], '2026-04-08T10:20:00.000Z');
    });

    test('returns false and requests reconnect when local register validation fails', () async {
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(true);
      final neg = buildNegotiator(agentIdProvider: () => '');

      final sent = await neg.sendRegisterAndStartTimeout();

      expect(sent, isFalse);
      expect(emitted, isEmpty);
      expect(reconnectCalls, 1);
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

  group('handleRegisterError', () {
    test('returns false and keeps socket open for recoverable register errors', () {
      final neg = buildNegotiator();
      addTearDown(neg.reset);

      final shouldReconnect = neg.handleRegisterError({
        'code': -32603,
        'reason': 'transient_failure',
        'message': 'try again',
      });

      expect(shouldReconnect, isFalse);
      expect(reconnectCalls, 0);
    });

    test('returns false for rate_limited without closing the socket', () {
      final neg = buildNegotiator();
      addTearDown(neg.reset);

      final shouldReconnect = neg.handleRegisterError({
        'code': -32013,
        'reason': 'rate_limited',
        'message': 'too many register attempts',
      });

      expect(shouldReconnect, isFalse);
      expect(reconnectCalls, 0);
    });

    test('returns true for hub wire authentication_failed (reason field)', () {
      final neg = buildNegotiator();

      final shouldReconnect = neg.handleRegisterError({
        'code': -32001,
        'reason': 'authentication_failed',
        'message': 'authentication failed',
      });

      expect(shouldReconnect, isTrue);
      expect(reconnectCalls, 1);
    });

    test('returns true for session_active (reject_active policy)', () {
      final neg = buildNegotiator();

      final shouldReconnect = neg.handleRegisterError({
        'code': -32014,
        'reason': 'session_active',
        'message': 'another session is active',
        'details': {'code': 'same_agent_session_active'},
      });

      expect(shouldReconnect, isTrue);
      expect(reconnectCalls, 1);
    });

    test('returns true for internal_error even when code matches transient (-32603)', () {
      final neg = buildNegotiator();

      final shouldReconnect = neg.handleRegisterError({
        'code': -32603,
        'reason': 'internal_error',
        'message': 'unexpected hub failure',
      });

      expect(shouldReconnect, isTrue);
      expect(reconnectCalls, 1);
    });

    test('returns true for legacy string code auth_failed without reason', () {
      final neg = buildNegotiator();

      final shouldReconnect = neg.handleRegisterError({
        'code': 'auth_failed',
        'message': 'authentication failed',
      });

      expect(shouldReconnect, isTrue);
      expect(reconnectCalls, 1);
    });

    test('returns true for unknown reasons (terminal by default)', () {
      // Unknown reasons force reconnect so auth/session failures are not
      // silently retried on the same socket (aligned with hub register_error).
      final neg = buildNegotiator();

      for (final unknownReason in ['unsupported_protocol', 'new_future_code', 'unknown_error']) {
        reconnectCalls = 0;
        final shouldReconnect = neg.handleRegisterError({
          'code': -32600,
          'reason': unknownReason,
          'message': 'msg',
        });
        expect(shouldReconnect, isTrue, reason: 'reason=$unknownReason should be terminal');
        expect(reconnectCalls, 1, reason: 'reason=$unknownReason should trigger reconnect');
      }
    });

    test('returns true when only a numeric code is present (ambiguous without reason)', () {
      final neg = buildNegotiator();

      final shouldReconnect = neg.handleRegisterError({
        'code': -32001,
        'message': 'missing reason',
      });

      expect(shouldReconnect, isTrue);
      expect(reconnectCalls, 1);
    });

    test('should return false from sendRegisterAndStartTimeout when emit fails (H2)', () async {
      // Simulate _emitEventAsync returning false (encode failure / socket null)
      final failingEmitNeg = CapabilitiesNegotiator(
        negotiator: negotiator,
        featureFlags: featureFlags,
        contractValidator: const RpcContractValidator(),
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        agentIdProvider: () => 'agent-1',
        emit: (event, payload) async => false,
        decodeIncoming: (payload, {String? sourceEvent}) =>
            Success<Object, Exception>(payload as Object) as Result<dynamic>,
        onTimeoutReconnect: () => reconnectCalls++,
      );
      addTearDown(failingEmitNeg.reset);

      final sent = await failingEmitNeg.sendRegisterAndStartTimeout();

      expect(sent, isFalse);
      expect(reconnectCalls, 1);
    });
  });

  group('handleEnvelope - failure', () {
    test('returns failure outcome when negotiated protocol violates contract', () {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(
        const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
        ),
      );

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

    test('returns failure when capabilities field is missing', () {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(binaryProtocol());

      final neg = buildNegotiator();
      final outcome = neg.handleEnvelope(<String, dynamic>{
        'agentId': 'agent-1',
      });

      expect(outcome, isA<CapabilitiesNegotiationFailure>());
      expect(neg.hasReceivedCapabilities, isFalse);
      verifyNever(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      );
    });
  });

  group('capabilities timeout', () {
    test('re-registers when timer fires before hub responds', () {
      fakeAsync((async) {
        final neg = buildNegotiator();

        unawaited(neg.sendRegisterAndStartTimeout());
        async.flushMicrotasks();

        expect(emitted, hasLength(1));
        expect(reconnectCalls, 0);

        async.elapse(
          const Duration(milliseconds: ConnectionConstants.capabilitiesTimeoutMs),
        );
        async.flushMicrotasks();

        expect(emitted, hasLength(2));
        expect(emitted.every((item) => item.event == 'agent:register'), isTrue);
        expect(reconnectCalls, 0);

        neg.reset();
      });
    });

    test('calls onTimeoutReconnect after max re-register attempts are exhausted', () {
      fakeAsync((async) {
        final neg = buildNegotiator();

        unawaited(neg.sendRegisterAndStartTimeout());
        async.flushMicrotasks();

        for (var attempt = 0; attempt < ConnectionConstants.capabilitiesMaxReRegisterAttempts; attempt++) {
          async.elapse(
            const Duration(milliseconds: ConnectionConstants.capabilitiesTimeoutMs),
          );
          async.flushMicrotasks();
        }

        expect(
          emitted.where((item) => item.event == 'agent:register').length,
          ConnectionConstants.capabilitiesMaxReRegisterAttempts + 1,
        );
        expect(reconnectCalls, 0);

        async.elapse(
          const Duration(milliseconds: ConnectionConstants.capabilitiesTimeoutMs),
        );
        async.flushMicrotasks();

        expect(reconnectCalls, 1);
        expect(
          emitted.where((item) => item.event == 'agent:register').length,
          ConnectionConstants.capabilitiesMaxReRegisterAttempts + 1,
        );

        neg.reset();
      });
    });

    test('does not re-register after capabilities are received', () {
      when(
        () => negotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
        ),
      ).thenReturn(binaryProtocol());

      fakeAsync((async) {
        final neg = buildNegotiator();

        unawaited(neg.sendRegisterAndStartTimeout());
        async.flushMicrotasks();

        neg.handleEnvelope({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        });

        async.elapse(
          const Duration(
            milliseconds:
                ConnectionConstants.capabilitiesTimeoutMs * (ConnectionConstants.capabilitiesMaxReRegisterAttempts + 2),
          ),
        );
        async.flushMicrotasks();

        expect(emitted, hasLength(1));
        expect(reconnectCalls, 0);

        neg.reset();
      });
    });
  });

  group('parallelBatchDispatch negotiation', () {
    CapabilitiesNegotiator buildRealNegotiator({
      ProtocolCapabilities Function()? localCapabilitiesProvider,
    }) {
      return CapabilitiesNegotiator(
        negotiator: ProtocolNegotiator(),
        featureFlags: featureFlags,
        contractValidator: const RpcContractValidator(),
        localCapabilitiesProvider:
            localCapabilitiesProvider ??
            () => ProtocolCapabilities.defaultCapabilities(
              parallelBatchDispatch: ParallelBatchDispatchNegotiation.agentAdvertisement(enabled: true),
            ),
        agentIdProvider: () => 'agent-1',
        emit: (event, payload) async {
          emitted.add((event: event, payload: payload));
          return true;
        },
        decodeIncoming: (payload, {String? sourceEvent}) {
          return Success<Object, Exception>(payload as Object) as Result<dynamic>;
        },
        onTimeoutReconnect: () => reconnectCalls++,
      );
    }

    test('should advertise parallelBatchDispatch in agent:register capabilities', () async {
      final neg = buildRealNegotiator();
      addTearDown(neg.reset);

      final sent = await neg.sendRegisterAndStartTimeout();

      expect(sent, isTrue);
      final payload = emitted.single.payload as Map<String, dynamic>;
      final capabilities = payload['capabilities'] as Map<String, dynamic>;
      final extensions = capabilities['extensions'] as Map<String, dynamic>;
      expect(extensions['parallelBatchDispatch'], {
        'enabled': true,
        'maxConcurrency': 4,
        'mixedReadOnlyMethods': true,
        'selectOnlySqlExecute': true,
      });
    });

    test('should negotiate parallelBatchDispatch intersection in handleEnvelope', () {
      final neg = buildRealNegotiator();
      final outcome = neg.handleEnvelope({
        'capabilities': const ProtocolCapabilities(
          protocols: ['jsonrpc-v2'],
          encodings: ['json'],
          compressions: ['gzip', 'none'],
          extensions: {
            'binaryPayload': true,
            'transportFrame': 'payload-frame/1.0',
            'parallelBatchDispatch': {
              'enabled': true,
              'maxConcurrency': 2,
              'mixedReadOnlyMethods': true,
              'selectOnlySqlExecute': false,
            },
          },
        ).toJson(),
      });

      expect(outcome, isA<CapabilitiesNegotiationSuccess>());
      final negotiated = (outcome as CapabilitiesNegotiationSuccess).negotiatedProtocol;
      expect(negotiated.negotiatedExtensions['parallelBatchDispatch'], {
        'enabled': true,
        'maxConcurrency': 2,
        'mixedReadOnlyMethods': true,
        'selectOnlySqlExecute': false,
      });
    });

    test('should omit parallelBatchDispatch when server disables the extension', () {
      final neg = buildRealNegotiator();
      final outcome = neg.handleEnvelope({
        'capabilities': const ProtocolCapabilities(
          protocols: ['jsonrpc-v2'],
          encodings: ['json'],
          compressions: ['gzip', 'none'],
          extensions: {
            'binaryPayload': true,
            'transportFrame': 'payload-frame/1.0',
            'parallelBatchDispatch': {
              'enabled': false,
            },
          },
        ).toJson(),
      });

      expect(outcome, isA<CapabilitiesNegotiationSuccess>());
      final negotiated = (outcome as CapabilitiesNegotiationSuccess).negotiatedProtocol;
      expect(negotiated.negotiatedExtensions.containsKey('parallelBatchDispatch'), isFalse);
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
