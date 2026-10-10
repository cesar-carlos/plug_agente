import 'package:flutter/foundation.dart';

@immutable
class ClientTokenSecretFeedback {
  const ClientTokenSecretFeedback({
    required this.tokenId,
    required this.clientId,
    required this.tokenValue,
    required this.version,
    required this.isCreation,
  });

  final String tokenId;
  final String clientId;
  final String tokenValue;
  final int version;
  final bool isCreation;
}
