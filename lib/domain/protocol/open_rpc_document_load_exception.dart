/// Thrown when the OpenRPC document cannot be loaded from the asset bundle or
/// disk. Callers should surface this as an RPC error instead of advertising
/// zero methods.
class OpenRpcDocumentLoadException implements Exception {
  OpenRpcDocumentLoadException({
    required this.message,
    this.assetError,
    this.fileError,
    this.cwd,
  });

  final String message;
  final Object? assetError;
  final Object? fileError;
  final String? cwd;

  @override
  String toString() => 'OpenRpcDocumentLoadException: $message';
}
