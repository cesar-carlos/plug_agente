class ClientTokenVersionConflictException implements Exception {
  const ClientTokenVersionConflictException({required this.currentVersion});

  final int currentVersion;

  @override
  String toString() => 'ClientTokenVersionConflictException(currentVersion: $currentVersion)';
}
