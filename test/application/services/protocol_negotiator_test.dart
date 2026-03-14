import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

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

    test('should keep jsonrpc-v2 when there is no common protocol', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      const serverCaps = ProtocolCapabilities(
        protocols: ['custom-v3'],
        encodings: ['json'],
        compressions: ['none'],
      );

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.protocol, equals('jsonrpc-v2'));
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
          'errorFormat': 'problem-details-inspired',
          'plugProfile': 'plug-jsonrpc-profile/2.4',
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
        equals('plug-jsonrpc-profile/2.4'),
      );
    });
  });
}
