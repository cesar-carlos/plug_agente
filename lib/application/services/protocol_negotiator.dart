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
    final commonProtocols = agentCapabilities.protocols.where(serverCapabilities.protocols.contains).toList();
    final selectedProtocol =
        preferJsonRpcV2 && commonProtocols.contains('jsonrpc-v2') && agentCapabilities.supportsJsonRpcV2
        ? 'jsonrpc-v2'
        : (commonProtocols.isNotEmpty ? commonProtocols.first : 'jsonrpc-v2');

    // 2. Select encoding (prefer json for compatibility)
    final commonEncodings = agentCapabilities.encodings.where(serverCapabilities.encodings.contains).toList();

    final selectedEncoding = commonEncodings.contains('json')
        ? 'json'
        : (commonEncodings.isNotEmpty ? commonEncodings.first : 'json');

    // 3. Select compression (prefer gzip if both support it)
    final commonCompressions = agentCapabilities.compressions.where(serverCapabilities.compressions.contains).toList();

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
    final compressionThreshold = _negotiateCompressionThreshold(
      agentCapabilities.extensions,
      serverCapabilities.extensions,
    );
    final maxInflationRatio = _negotiateMaxInflationRatio(
      agentCapabilities.extensions,
      serverCapabilities.extensions,
    );
    final signatureAlgorithms = _intersectStringLists(
      agentCapabilities.extensions['signatureAlgorithms'],
      serverCapabilities.extensions['signatureAlgorithms'],
    );
    final signatureRequired = _negotiateSignatureRequired(
      agentCapabilities.extensions,
      serverCapabilities.extensions,
      signatureAlgorithms,
    );

    return ProtocolConfig(
      protocol: selectedProtocol,
      encoding: selectedEncoding,
      compression: selectedCompression,
      compressionThreshold: compressionThreshold,
      maxInflationRatio: maxInflationRatio,
      signatureRequired: signatureRequired,
      signatureAlgorithms: signatureAlgorithms,
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
      signatureAlgorithms: ['hmac-sha256'],
      negotiatedExtensions: {
        'binaryPayload': true,
        'transportFrame': 'payload-frame/1.0',
        'compressionThreshold': 1024,
        'maxInflationRatio': 20,
        'signatureRequired': false,
        'signatureScope': 'transport-frame',
        'signatureAlgorithms': ['hmac-sha256'],
      },
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
        (agentExtensions['notificationNullIdCompatibility'] as bool? ?? false) &&
        (serverExtensions['notificationNullIdCompatibility'] as bool? ?? false);
    if (notificationNullIdCompatibility) {
      negotiated['notificationNullIdCompatibility'] = true;
    }

    final protocolReadyAck =
        (agentExtensions['protocolReadyAck'] as bool? ?? false) &&
        (serverExtensions['protocolReadyAck'] as bool? ?? false);
    if (protocolReadyAck) {
      negotiated['protocolReadyAck'] = true;
    }

    final binaryPayload =
        (agentExtensions['binaryPayload'] as bool? ?? false) && (serverExtensions['binaryPayload'] as bool? ?? false);
    if (binaryPayload) {
      negotiated['binaryPayload'] = true;
    }

    final transportFrame = agentExtensions['transportFrame'];
    if (transportFrame != null && transportFrame == serverExtensions['transportFrame']) {
      negotiated['transportFrame'] = transportFrame;
    }

    final compressionThreshold = _negotiateCompressionThreshold(
      agentExtensions,
      serverExtensions,
    );
    negotiated['compressionThreshold'] = compressionThreshold;

    final maxInflationRatio = _negotiateMaxInflationRatio(
      agentExtensions,
      serverExtensions,
    );
    negotiated['maxInflationRatio'] = maxInflationRatio;

    final signatureAlgorithms = _intersectStringLists(
      agentExtensions['signatureAlgorithms'],
      serverExtensions['signatureAlgorithms'],
    );
    if (signatureAlgorithms.isNotEmpty) {
      negotiated['signatureAlgorithms'] = signatureAlgorithms;
    }

    final signatureScope = agentExtensions['signatureScope'];
    if (signatureScope != null && signatureScope == serverExtensions['signatureScope']) {
      negotiated['signatureScope'] = signatureScope;
    }

    final signatureRequired = _negotiateSignatureRequired(
      agentExtensions,
      serverExtensions,
      signatureAlgorithms,
    );
    negotiated['signatureRequired'] = signatureRequired;

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

    // Backpressure window hints: pick the minimum of agent and server values so
    // both sides agree on a safe upper bound. Recommended is also clamped by
    // the negotiated max so the recommended value never exceeds the cap.
    final maxStreamPullWindowSize = _negotiateMinPositiveInt(
      agentExtensions['maxStreamPullWindowSize'],
      serverExtensions['maxStreamPullWindowSize'],
    );
    if (maxStreamPullWindowSize != null) {
      negotiated['maxStreamPullWindowSize'] = maxStreamPullWindowSize;
    }
    final recommendedRaw = _negotiateMinPositiveInt(
      agentExtensions['recommendedStreamPullWindowSize'],
      serverExtensions['recommendedStreamPullWindowSize'],
    );
    if (recommendedRaw != null) {
      final clamped = maxStreamPullWindowSize != null && recommendedRaw > maxStreamPullWindowSize
          ? maxStreamPullWindowSize
          : recommendedRaw;
      negotiated['recommendedStreamPullWindowSize'] = clamped;
    }

    return negotiated;
  }

  int? _negotiateMinPositiveInt(dynamic agentValue, dynamic serverValue) {
    final agentInt = agentValue is int && agentValue > 0 ? agentValue : null;
    final serverInt = serverValue is int && serverValue > 0 ? serverValue : null;
    if (agentInt == null && serverInt == null) return null;
    if (agentInt == null) return serverInt;
    if (serverInt == null) return agentInt;
    return agentInt < serverInt ? agentInt : serverInt;
  }

  int _negotiateCompressionThreshold(
    Map<String, dynamic> agentExtensions,
    Map<String, dynamic> serverExtensions,
  ) {
    final agentValue = agentExtensions['compressionThreshold'];
    final serverValue = serverExtensions['compressionThreshold'];
    final agentThreshold = agentValue is int && agentValue > 0 ? agentValue : 1024;
    final serverThreshold = serverValue is int && serverValue > 0 ? serverValue : 1024;
    return agentThreshold < serverThreshold ? agentThreshold : serverThreshold;
  }

  double _negotiateMaxInflationRatio(
    Map<String, dynamic> agentExtensions,
    Map<String, dynamic> serverExtensions,
  ) {
    final agentValue = agentExtensions['maxInflationRatio'];
    final serverValue = serverExtensions['maxInflationRatio'];
    final agentRatio = agentValue is num && agentValue >= 1 ? agentValue.toDouble() : 20;
    final serverRatio = serverValue is num && serverValue >= 1 ? serverValue.toDouble() : 20;
    return (agentRatio < serverRatio ? agentRatio : serverRatio).toDouble();
  }

  bool _negotiateSignatureRequired(
    Map<String, dynamic> agentExtensions,
    Map<String, dynamic> serverExtensions,
    List<String> signatureAlgorithms,
  ) {
    final required =
        (agentExtensions['signatureRequired'] as bool? ?? false) ||
        (serverExtensions['signatureRequired'] as bool? ?? false);
    if (!required) {
      return false;
    }
    return signatureAlgorithms.isNotEmpty;
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
