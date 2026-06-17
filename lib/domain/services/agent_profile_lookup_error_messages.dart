class OpenCnpjLookupErrorMessages {
  const OpenCnpjLookupErrorMessages({
    required this.emptyResponse,
    required this.invalidPayload,
    required this.notFound,
    required this.rateLimit,
    required this.networkError,
    required this.unexpectedError,
  });

  final String emptyResponse;
  final String invalidPayload;
  final String notFound;
  final String rateLimit;
  final String networkError;
  final String unexpectedError;
}

class ViaCepLookupErrorMessages {
  const ViaCepLookupErrorMessages({
    required this.emptyResponse,
    required this.notFound,
    required this.invalidPayload,
    required this.networkError,
    required this.unexpectedError,
  });

  final String emptyResponse;
  final String notFound;
  final String invalidPayload;
  final String networkError;
  final String unexpectedError;
}
