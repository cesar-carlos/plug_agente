class ClientTokenCreationResult {
  const ClientTokenCreationResult({
    required this.tokenId,
    required this.tokenValue,
    this.version = 1,
  });

  final String tokenId;
  final String tokenValue;
  final int version;
}
