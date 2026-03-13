import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

/// Service for negotiating protocol configuration between client and server.
class ProtocolNegotiator {
  /// Negotiates protocol configuration based on agent and server capabilities.
  ///
  /// Returns the best mutually supported configuration.
  ProtocolConfig negotiate({
    required ProtocolCapabilities agentCapabilities,
    required ProtocolCapabilities serverCapabilities,
    bool preferJsonRpcV2 = true,
  }) {
    // 1. Select protocol (prefer v2 if both support it and preferJsonRpcV2 is true)
    String selectedProtocol;

    if (preferJsonRpcV2 &&
        agentCapabilities.supportsJsonRpcV2 &&
        serverCapabilities.supportsJsonRpcV2) {
      selectedProtocol = 'jsonrpc-v2';
    } else if (agentCapabilities.supportsLegacyV1 &&
        serverCapabilities.supportsLegacyV1) {
      selectedProtocol = 'legacy-envelope-v1';
    } else {
      // Fallback to first common protocol
      final commonProtocols = agentCapabilities.protocols
          .where(serverCapabilities.protocols.contains)
          .toList();

      if (commonProtocols.isEmpty) {
        // No common protocol, use legacy as last resort
        selectedProtocol = 'legacy-envelope-v1';
      } else {
        selectedProtocol = commonProtocols.first;
      }
    }

    // 2. Select encoding (prefer json for compatibility)
    final commonEncodings = agentCapabilities.encodings
        .where(serverCapabilities.encodings.contains)
        .toList();

    final selectedEncoding = commonEncodings.contains('json')
        ? 'json'
        : (commonEncodings.isNotEmpty ? commonEncodings.first : 'json');

    // 3. Select compression (prefer gzip if both support it)
    final commonCompressions = agentCapabilities.compressions
        .where(serverCapabilities.compressions.contains)
        .toList();

    final selectedCompression = commonCompressions.contains('gzip')
        ? 'gzip'
        : (commonCompressions.isNotEmpty ? commonCompressions.first : 'none');

    final effectiveLimits =
        agentCapabilities.limits.negotiateWith(serverCapabilities.limits);

    return ProtocolConfig(
      protocol: selectedProtocol,
      encoding: selectedEncoding,
      compression: selectedCompression,
      effectiveLimits: effectiveLimits,
    );
  }

  /// Validates if a protocol configuration is supported by the agent.
  bool isSupported(
    ProtocolConfig config,
    ProtocolCapabilities agentCapabilities,
  ) {
    return agentCapabilities.supportsProtocol(config.protocol) &&
        agentCapabilities.supportsEncoding(config.encoding) &&
        agentCapabilities.supportsCompression(config.compression);
  }

  /// Creates a fallback configuration (legacy-only).
  ProtocolConfig createFallbackConfig() {
    return const ProtocolConfig(
      protocol: 'legacy-envelope-v1',
      encoding: 'json',
      compression: 'none',
    );
  }
}
