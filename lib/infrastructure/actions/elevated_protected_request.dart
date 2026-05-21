/// Metadata written alongside an elevated execution request file.
class ElevatedProtectedRequest {
  const ElevatedProtectedRequest({
    required this.executionId,
    required this.nonce,
    required this.expiresAt,
    required this.requestPath,
  });

  final String executionId;
  final String nonce;
  final DateTime expiresAt;
  final String requestPath;
}
