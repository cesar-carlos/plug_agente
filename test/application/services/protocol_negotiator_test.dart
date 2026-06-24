import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/constants/protocol_version.dart';
import 'package:plug_agente/core/constants/rpc_batch_negotiation.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/transport_extension_negotiation.dart';

void main() {
  group('ProtocolNegotiator', () {
    late ProtocolNegotiator negotiator;

    setUp(() {
      negotiator = ProtocolNegotiator();
    });

    test('should select jsonrpc-v2 when both support it and preferred', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverCaps = ProtocolCapabilities.defaultCapabilities();

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.protocol, equals('jsonrpc-v2'));
    });

    test('should throw StateError when there is no common protocol', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      const serverCaps = ProtocolCapabilities(
        protocols: ['custom-v3'],
        encodings: ['json'],
        compressions: ['none'],
      );

      expect(
        () => negotiator.negotiate(
          agentCapabilities: agentCaps,
          serverCapabilities: serverCaps,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('should keep the first common protocol when v2 is not preferred', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      const serverCaps = ProtocolCapabilities(
        protocols: ['jsonrpc-v2'],
        encodings: ['json'],
        compressions: ['gzip', 'none'],
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
        preferJsonRpcV2: false,
      );

      expect(config.protocol, equals('jsonrpc-v2'));
    });

    test('should select gzip compression when both support it', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverCaps = ProtocolCapabilities.defaultCapabilities();

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.compression, equals('gzip'));
      expect(config.compressionThreshold, equals(4096));
      expect(config.maxInflationRatio, equals(10));
      expect(config.negotiatedExtensions['binaryPayload'], isTrue);
      expect(
        config.negotiatedExtensions['transportFrame'],
        'payload-frame/1.0',
      );
      expect(
        config.negotiatedExtensions['paginationModes'],
        contains('cursor-offset'),
      );
    });

    test('should select json encoding when both support it', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverCaps = ProtocolCapabilities.defaultCapabilities();

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.encoding, equals('json'));
    });

    test('should validate if configuration is supported', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      const config = ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
      );

      final isSupported = negotiator.isSupported(config, agentCaps);

      expect(isSupported, isTrue);
    });

    test('should return false when configuration is not supported', () {
      const agentCaps = ProtocolCapabilities(
        protocols: ['custom-v3'],
        encodings: ['json'],
        compressions: ['none'],
      );
      const config = ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
      );

      final isSupported = negotiator.isSupported(config, agentCaps);

      expect(isSupported, isFalse);
    });

    test('should create fallback configuration', () {
      final config = negotiator.createFallbackConfig();

      expect(config.protocol, equals('jsonrpc-v2'));
      expect(config.encoding, equals('json'));
      expect(config.compression, equals('none'));
      expect(config.compressionThreshold, equals(4096));
      expect(config.maxInflationRatio, equals(10));
      expect(config.usesBinaryPayload, isTrue);
      expect(config.usesTransportFrame, isTrue);
    });

    test('should negotiate plug profile extensions intersection', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      const serverCaps = ProtocolCapabilities(
        protocols: ['jsonrpc-v2'],
        encodings: ['json'],
        compressions: ['none'],
        extensions: {
          'orderedBatchResponses': true,
          'notificationNullIdCompatibility': true,
          'paginationModes': ['cursor-keyset'],
          'traceContext': ['w3c-trace-context'],
          'errorFormat': 'structured-error-data',
          'plugProfile': ProtocolVersion.plugProfile,
        },
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(
        config.negotiatedExtensions['paginationModes'],
        equals(['cursor-keyset']),
      );
      expect(
        config.negotiatedExtensions['traceContext'],
        equals(['w3c-trace-context']),
      );
      expect(
        config.negotiatedExtensions['plugProfile'],
        equals(ProtocolVersion.plugProfile),
      );
    });

    test('should negotiate parallelBatchDispatch extension intersection', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities(
        parallelBatchDispatch: ParallelBatchDispatchNegotiation.agentAdvertisement(enabled: true),
      );
      const serverCaps = ProtocolCapabilities(
        protocols: ['jsonrpc-v2'],
        encodings: ['json'],
        compressions: ['none'],
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
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.negotiatedExtensions['parallelBatchDispatch'], {
        'enabled': true,
        'maxConcurrency': 2,
        'mixedReadOnlyMethods': true,
        'selectOnlySqlExecute': false,
      });
    });

    test('should negotiate streaming results only when both sides support it', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities(
        streamingResults: true,
      );
      final serverCaps = ProtocolCapabilities.defaultCapabilities(
        streamingResults: true,
      );

      final enabled = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(enabled.negotiatedExtensions['streamingResults'], isTrue);

      final disabled = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: ProtocolCapabilities.defaultCapabilities(),
      );

      expect(disabled.negotiatedExtensions['streamingResults'], isFalse);
    });

    test('should negotiate signature policy and algorithms', () {
      const agentCaps = ProtocolCapabilities(
        protocols: ['jsonrpc-v2'],
        encodings: ['json'],
        compressions: ['gzip', 'none'],
        extensions: {
          'binaryPayload': true,
          'transportFrame': 'payload-frame/1.0',
          'compressionThreshold': 2048,
          'maxInflationRatio': 10,
          'signatureRequired': true,
          'signatureScope': 'transport-frame',
          'signatureAlgorithms': ['hmac-sha256'],
        },
      );
      const serverCaps = ProtocolCapabilities(
        protocols: ['jsonrpc-v2'],
        encodings: ['json'],
        compressions: ['gzip', 'none'],
        extensions: {
          'binaryPayload': true,
          'transportFrame': 'payload-frame/1.0',
          'compressionThreshold': 4096,
          'maxInflationRatio': 20,
          'signatureRequired': false,
          'signatureScope': 'transport-frame',
          'signatureAlgorithms': ['hmac-sha256', 'ed25519'],
        },
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.compressionThreshold, 2048);
      expect(config.maxInflationRatio, 10);
      expect(config.signatureRequired, isTrue);
      expect(config.signatureAlgorithms, ['hmac-sha256']);
    });

    test('should negotiate performance observability extensions when hub echoes them', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverCaps = ProtocolCapabilities(
        protocols: agentCaps.protocols,
        encodings: agentCaps.encodings,
        compressions: agentCaps.compressions,
        extensions: {
          ...agentCaps.extensions,
        },
        limits: agentCaps.limits,
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(
        config.negotiatedExtensions[TransportExtensionNegotiation.clientRequestIdEcho],
        TransportExtensionNegotiation.clientRequestIdEchoVersion,
      );
      expect(
        config.negotiatedExtensions[TransportExtensionNegotiation.agentPhaseTimings],
        TransportExtensionNegotiation.agentPhaseTimingsVersion,
      );
      expect(
        config.negotiatedExtensions[TransportExtensionNegotiation.healthPiggyback],
        isA<Map<String, dynamic>>(),
      );
    });

    test('should omit performance observability extensions when hub does not advertise them', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverExtensions = Map<String, dynamic>.from(agentCaps.extensions)
        ..remove(TransportExtensionNegotiation.clientRequestIdEcho)
        ..remove(TransportExtensionNegotiation.agentPhaseTimings)
        ..remove(TransportExtensionNegotiation.healthPiggyback);
      final serverCaps = ProtocolCapabilities(
        protocols: agentCaps.protocols,
        encodings: agentCaps.encodings,
        compressions: agentCaps.compressions,
        extensions: serverExtensions,
        limits: agentCaps.limits,
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.negotiatedExtensions.containsKey(TransportExtensionNegotiation.clientRequestIdEcho), isFalse);
      expect(config.negotiatedExtensions.containsKey(TransportExtensionNegotiation.agentPhaseTimings), isFalse);
      expect(config.negotiatedExtensions.containsKey(TransportExtensionNegotiation.healthPiggyback), isFalse);
    });
  });
}
