/// Centralized protocol version constants.
///
/// Single source of truth for api_version, plug profile, and OpenRPC version
/// to avoid drift between protocol_capabilities, transport client, and openrpc.json.
class ProtocolVersion {
  ProtocolVersion._();

  /// API version for RPC payloads (e.g. "2.8").
  static const String apiVersion = '2.8';

  /// Plug JSON-RPC profile identifier (e.g. "plug-jsonrpc-profile/2.8").
  static const String plugProfile = 'plug-jsonrpc-profile/2.8';

  /// OpenRPC document info.version (semantic version, e.g. "2.8.0").
  static const String openRpcVersion = '2.8.0';
}
