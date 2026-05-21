/// Pure-Dart helpers to export PayloadFrame signing keys into `.env` from
/// decrypted Plug Agente secure storage (Windows).
library;

import 'dart:convert';

/// Result of attempting to read signing material from secure storage keys.
class E2ePayloadSigningExportCandidate {
  const E2ePayloadSigningExportCandidate({
    required this.keyId,
    required this.secret,
    this.activeKeyId,
  });

  final String keyId;
  final String secret;
  final String? activeKeyId;
}

/// Parses signing keys using the same secure-storage key names as the app store.
E2ePayloadSigningExportCandidate? readPayloadSigningFromSecureStorageMap(
  Map<String, String> storage,
) {
  final keysJsonRaw = storage['payload_signing_keys_json']?.trim();
  final activeKeyId = storage['payload_signing_active_key_id']?.trim();
  if (keysJsonRaw != null && keysJsonRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(keysJsonRaw);
      if (decoded is Map<String, dynamic>) {
        final keys = <String, String>{};
        for (final entry in decoded.entries) {
          if (entry.value is String && entry.value.toString().trim().isNotEmpty) {
            keys[entry.key] = entry.value as String;
          }
        }
        final keyId = activeKeyId ?? (keys.isEmpty ? null : keys.keys.first);
        if (keyId != null && keys.containsKey(keyId)) {
          return E2ePayloadSigningExportCandidate(
            keyId: keyId,
            secret: keys[keyId]!,
            activeKeyId: activeKeyId,
          );
        }
      }
    } on FormatException {
      return null;
    }
  }

  final legacyKey = storage['PAYLOAD_SIGNING_KEY']?.trim();
  final legacyKeyId = storage['PAYLOAD_SIGNING_KEY_ID']?.trim();
  if (legacyKey != null && legacyKey.isNotEmpty && legacyKeyId != null && legacyKeyId.isNotEmpty) {
    return E2ePayloadSigningExportCandidate(
      keyId: legacyKeyId,
      secret: legacyKey,
    );
  }

  return null;
}

/// Key names in secure storage that look related to payload signing (for hints).
List<String> listPayloadSigningRelatedStorageKeys(Map<String, String> storage) {
  return storage.keys
      .where(
        (key) => key.toLowerCase().contains('payload_signing') || key.toUpperCase().contains('PAYLOAD_SIGNING'),
      )
      .toList()
    ..sort();
}
