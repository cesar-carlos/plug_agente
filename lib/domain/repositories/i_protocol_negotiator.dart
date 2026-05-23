import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

/// Negotiates mutually supported protocol configuration between agent and hub.
abstract class IProtocolNegotiator {
  ProtocolConfig negotiate({
    required ProtocolCapabilities agentCapabilities,
    required ProtocolCapabilities serverCapabilities,
    bool preferJsonRpcV2 = true,
  });
}
