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

    test('should fallback to legacy when server only supports legacy', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverCaps = ProtocolCapabilities.legacyOnly();

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
      );

      expect(config.protocol, equals('legacy-envelope-v1'));
    });

    test('should fallback to legacy when preferJsonRpcV2 is false', () {
      final agentCaps = ProtocolCapabilities.defaultCapabilities();
      final serverCaps = ProtocolCapabilities.defaultCapabilities();

      final config = negotiator.negotiate(
        agentCapabilities: agentCaps,
        serverCapabilities: serverCaps,
        preferJsonRpcV2: false,
      );

      expect(config.protocol, equals('legacy-envelope-v1'));
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
      final agentCaps = ProtocolCapabilities.legacyOnly();
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

      expect(config.protocol, equals('legacy-envelope-v1'));
      expect(config.encoding, equals('json'));
      expect(config.compression, equals('none'));
    });
  });
}
