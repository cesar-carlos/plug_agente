class ClientTokenSecretLookup {
  const ClientTokenSecretLookup({required this.tokenValue});

  final String? tokenValue;

  bool get isAvailable => tokenValue?.trim().isNotEmpty ?? false;
}
