import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String hashStoredClientToken(String token) {
  final bytes = utf8.encode(token);
  return sha256.convert(bytes).toString();
}

String generateOpaqueClientToken(Random random) {
  const tokenLength = 32;
  final bytes = List<int>.generate(
    tokenLength,
    (_) => random.nextInt(256),
  );
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String buildClientTokenId(Random random) {
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  final suffix = random.nextInt(1 << 20).toRadixString(16);
  return '${timestamp}_$suffix';
}

String? normalizeClientTokenAgentId(String? agentId) {
  final trimmed = agentId?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String fallbackStoredClientTokenHash({
  required String tokenId,
  String? tokenValue,
}) {
  final normalized = tokenValue?.trim();
  if (normalized != null && normalized.isNotEmpty) {
    return hashStoredClientToken(normalized);
  }
  return 'missing:$tokenId';
}
