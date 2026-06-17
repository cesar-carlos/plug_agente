import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';

const Set<String> rpcInboundSqlDashboardCaptureMethods = <String>{
  'sql.execute',
  'sql.executeBatch',
};

bool rpcInboundShouldPauseDashboardCaptureForMethod(String method) {
  return rpcInboundSqlDashboardCaptureMethods.contains(method);
}

Map<Object?, String> rpcInboundMethodsByIdForValidationError({
  required dynamic id,
  required Object? method,
}) {
  if (method is String && rpcInboundShouldPauseDashboardCaptureForMethod(method)) {
    return <Object?, String>{id: method};
  }
  return const <Object?, String>{};
}

String? extractClientTokenFromRpcParams(dynamic params) {
  if (params is! Map<String, dynamic>) return null;
  final raw = params['client_token'] as String? ?? params['auth'] as String? ?? params['clientToken'] as String?;
  return raw != null && raw.trim().isNotEmpty ? raw.trim() : null;
}

bool rpcInboundExceedsPayloadLimit(
  dynamic payload, {
  required ProtocolConfig Function() protocolProvider,
  required PayloadLogSummarizer logSummarizer,
}) {
  final limit = protocolProvider().effectiveLimits.maxDecodedPayloadBytes;
  return logSummarizer.exceedsByteBudget(payload, limit);
}

bool rpcInboundHasNullIdCompatibilityViolation(
  Map<String, dynamic> requestMap, {
  required ProtocolConfig Function() protocolProvider,
}) {
  return requestMap.containsKey('id') && requestMap['id'] == null && !_allowsNullIdNotifications(protocolProvider);
}

bool _allowsNullIdNotifications(ProtocolConfig Function() protocolProvider) {
  final extensionValue = protocolProvider().negotiatedExtensions['notificationNullIdCompatibility'];
  if (extensionValue is bool) return extensionValue;
  return true;
}

bool rpcInboundShouldCreateStreamEmitter({
  required RpcRequest request,
  required Map<String, dynamic> negotiatedExtensions,
  required FeatureFlags featureFlags,
}) {
  if (request.isNotification) {
    return false;
  }
  final negotiatedStreaming = negotiatedExtensions['streamingResults'] as bool? ?? false;
  return negotiatedStreaming &&
      (featureFlags.enableSocketStreamingChunks || featureFlags.enableSocketStreamingFromDb);
}
