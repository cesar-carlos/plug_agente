/// Stable diagnostic strings for `rpc.discover` OpenRPC load failures.
abstract final class OpenRpcConstants {
  static const String loadFailedFailureCode = 'openrpc_load_failed';

  static const String unavailableSubreason = 'openrpc_unavailable';

  static const String loadFailedTechnicalMessage =
      'OpenRPC document unavailable from asset bundle and disk';
}
