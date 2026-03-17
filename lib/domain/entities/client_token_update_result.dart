class ClientTokenUpdateResult {
  const ClientTokenUpdateResult({
    required this.tokenValue,
    required this.version,
    required this.updatedAt,
  });

  final String tokenValue;
  final int version;
  final DateTime updatedAt;
}
