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
    final commonProtocols = agentCapabilities.protocols
        .where(serverCapabilities.protocols.contains)
        .toList();
    final selectedProtocol =
        preferJsonRpcV2 &&
            commonProtocols.contains('jsonrpc-v2') &&
            agentCapabilities.supportsJsonRpcV2
        ? 'jsonrpc-v2'
        : (commonProtocols.isNotEmpty ? commonProtocols.first : 'jsonrpc-v2');

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

    final effectiveLimits = agentCapabilities.limits.negotiateWith(
      serverCapabilities.limits,
    );
    final negotiatedExtensions = _negotiateExtensions(
      agentCapabilities.extensions,
      serverCapabilities.extensions,
    );

    return ProtocolConfig(
      protocol: selectedProtocol,
      encoding: selectedEncoding,
      compression: selectedCompression,
      effectiveLimits: effectiveLimits,
      negotiatedExtensions: negotiatedExtensions,
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

  /// Creates a fallback configuration using the current v2 contract.
  ProtocolConfig createFallbackConfig() {
    return const ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'none',
    );
  }

  Map<String, dynamic> _negotiateExtensions(
    Map<String, dynamic> agentExtensions,
    Map<String, dynamic> serverExtensions,
  ) {
    final negotiated = <String, dynamic>{};

    final orderedBatchResponses =
        (agentExtensions['orderedBatchResponses'] as bool? ?? false) &&
        (serverExtensions['orderedBatchResponses'] as bool? ?? false);
    if (orderedBatchResponses) {
      negotiated['orderedBatchResponses'] = true;
    }

    final notificationNullIdCompatibility =
        (agentExtensions['notificationNullIdCompatibility'] as bool? ??
            false) &&
        (serverExtensions['notificationNullIdCompatibility'] as bool? ?? false);
    if (notificationNullIdCompatibility) {
      negotiated['notificationNullIdCompatibility'] = true;
    }

    final paginationModes = _intersectStringLists(
      agentExtensions['paginationModes'],
      serverExtensions['paginationModes'],
    );
    if (paginationModes.isNotEmpty) {
      negotiated['paginationModes'] = paginationModes;
    }

    final traceContext = _intersectStringLists(
      agentExtensions['traceContext'],
      serverExtensions['traceContext'],
    );
    if (traceContext.isNotEmpty) {
      negotiated['traceContext'] = traceContext;
    }

    final errorFormat = agentExtensions['errorFormat'];
    if (errorFormat != null && errorFormat == serverExtensions['errorFormat']) {
      negotiated['errorFormat'] = errorFormat;
    }

    final plugProfile = agentExtensions['plugProfile'];
    if (plugProfile != null && plugProfile == serverExtensions['plugProfile']) {
      negotiated['plugProfile'] = plugProfile;
    }

    return negotiated;
  }

  List<String> _intersectStringLists(dynamic a, dynamic b) {
    if (a is! List<dynamic> || b is! List<dynamic>) {
      return const [];
    }

    final left = a.whereType<String>().toSet();
    final right = b.whereType<String>().toSet();
    return left.intersection(right).toList()..sort();
  }
}
