enum PayloadSigningConfigSource {
  none,
  secureStorage,
  environment,
  environmentAndSecureStorage,
}

class PayloadSigningConfig {
  PayloadSigningConfig({
    String? activeKeyId,
    Map<String, String> keys = const <String, String>{},
    this.source = PayloadSigningConfigSource.none,
    this.secureStorageAvailable = true,
    Iterable<String> warnings = const <String>[],
  }) : activeKeyId = _normalize(activeKeyId),
       keys = Map.unmodifiable(_normalizeKeys(keys)),
       warnings = List.unmodifiable(warnings);

  factory PayloadSigningConfig.empty({
    bool secureStorageAvailable = true,
    Iterable<String> warnings = const <String>[],
  }) {
    return PayloadSigningConfig(
      secureStorageAvailable: secureStorageAvailable,
      warnings: warnings,
    );
  }

  final String? activeKeyId;
  final Map<String, String> keys;
  final PayloadSigningConfigSource source;
  final bool secureStorageAvailable;
  final List<String> warnings;

  bool get hasConfiguredSigner {
    final id = activeKeyId;
    return id != null && (keys[id]?.isNotEmpty ?? false);
  }

  int get keyCount => keys.length;

  List<String> get keyIds {
    final ids = keys.keys.toList()..sort();
    return List.unmodifiable(ids);
  }

  String get sourceName {
    return switch (source) {
      PayloadSigningConfigSource.none => 'none',
      PayloadSigningConfigSource.secureStorage => 'secure_storage',
      PayloadSigningConfigSource.environment => 'environment',
      PayloadSigningConfigSource.environmentAndSecureStorage => 'environment_and_secure_storage',
    };
  }

  PayloadSigningConfig copyWith({
    String? activeKeyId,
    Map<String, String>? keys,
    PayloadSigningConfigSource? source,
    bool? secureStorageAvailable,
    Iterable<String>? warnings,
  }) {
    return PayloadSigningConfig(
      activeKeyId: activeKeyId ?? this.activeKeyId,
      keys: keys ?? this.keys,
      source: source ?? this.source,
      secureStorageAvailable: secureStorageAvailable ?? this.secureStorageAvailable,
      warnings: warnings ?? this.warnings,
    );
  }

  PayloadSigningConfig upsertKey({
    required String keyId,
    required String secret,
    bool makeActive = false,
  }) {
    final normalizedKeyId = _normalize(keyId);
    final normalizedSecret = _normalize(secret);
    if (normalizedKeyId == null) {
      throw ArgumentError.value(keyId, 'keyId', 'Signing key id cannot be empty');
    }
    if (normalizedSecret == null) {
      throw ArgumentError.value(secret, 'secret', 'Signing key secret cannot be empty');
    }
    final nextKeys = <String, String>{
      ...keys,
      normalizedKeyId: normalizedSecret,
    };
    return PayloadSigningConfig(
      activeKeyId: makeActive ? normalizedKeyId : activeKeyId ?? normalizedKeyId,
      keys: nextKeys,
      source: source,
      secureStorageAvailable: secureStorageAvailable,
      warnings: warnings,
    );
  }

  PayloadSigningConfig activateKey(String keyId) {
    final normalizedKeyId = _normalize(keyId);
    if (normalizedKeyId == null || !keys.containsKey(normalizedKeyId)) {
      throw ArgumentError.value(keyId, 'keyId', 'Active signing key must exist in keys');
    }
    return PayloadSigningConfig(
      activeKeyId: normalizedKeyId,
      keys: keys,
      source: source,
      secureStorageAvailable: secureStorageAvailable,
      warnings: warnings,
    );
  }

  PayloadSigningConfig removeKey(String keyId) {
    final normalizedKeyId = _normalize(keyId);
    if (normalizedKeyId == null || !keys.containsKey(normalizedKeyId)) {
      return this;
    }
    final nextKeys = <String, String>{...keys}..remove(normalizedKeyId);
    final nextActiveKeyId = activeKeyId == normalizedKeyId ? _firstKeyId(nextKeys) : activeKeyId;
    return PayloadSigningConfig(
      activeKeyId: nextActiveKeyId,
      keys: nextKeys,
      source: source,
      secureStorageAvailable: secureStorageAvailable,
      warnings: warnings,
    );
  }

  static Map<String, String> _normalizeKeys(Map<String, String> raw) {
    final normalized = <String, String>{};
    for (final entry in raw.entries) {
      final keyId = _normalize(entry.key);
      final secret = _normalize(entry.value);
      if (keyId == null || secret == null) {
        continue;
      }
      normalized[keyId] = secret;
    }
    return normalized;
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String? _firstKeyId(Map<String, String> keys) {
    if (keys.isEmpty) {
      return null;
    }
    final ids = keys.keys.toList()..sort();
    return ids.first;
  }
}
