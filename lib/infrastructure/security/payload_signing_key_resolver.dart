import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';

abstract interface class PayloadSigningKeyStore {
  bool get isAvailable;

  Future<PayloadSigningConfig?> read();

  Future<void> save(PayloadSigningConfig config);
}

class NoopPayloadSigningKeyStore implements PayloadSigningKeyStore {
  const NoopPayloadSigningKeyStore();

  @override
  bool get isAvailable => false;

  @override
  Future<PayloadSigningConfig?> read() async => null;

  @override
  Future<void> save(PayloadSigningConfig config) async {}
}

class PayloadSigningKeyResolver {
  PayloadSigningKeyResolver({
    required PayloadSigningKeyStore keyStore,
    String? Function(String key)? environmentProvider,
    // Defaults to false so ephemeral CI/env secrets are never auto-persisted.
    // Set to true only when the operator explicitly imports keys via the UI.
    bool persistEnvironmentKeys = false,
  }) : _keyStore = keyStore,
       _environmentProvider = environmentProvider ?? AppEnvironment.get,
       _persistEnvironmentKeys = persistEnvironmentKeys;

  final PayloadSigningKeyStore _keyStore;
  final String? Function(String key) _environmentProvider;
  final bool _persistEnvironmentKeys;

  Future<PayloadSigningConfig> resolve() async {
    final stored = await _readStoredConfig();
    final envConfig = _readEnvironmentConfig();
    final warnings = <String>[
      ...?stored?.warnings,
      ...envConfig.warnings,
    ];

    if (envConfig.keys.isNotEmpty) {
      final mergedKeys = <String, String>{
        ...?stored?.keys,
        ...envConfig.keys,
      };
      final activeKeyId = envConfig.activeKeyId ?? stored?.activeKeyId ?? _firstKeyId(mergedKeys);
      final source = (stored?.keys.isNotEmpty ?? false)
          ? PayloadSigningConfigSource.environmentAndSecureStorage
          : PayloadSigningConfigSource.environment;
      final resolved = PayloadSigningConfig(
        activeKeyId: activeKeyId,
        keys: mergedKeys,
        source: source,
        secureStorageAvailable: _keyStore.isAvailable,
        warnings: warnings,
      );
      if (_persistEnvironmentKeys) {
        await _saveEnvironmentKeys(resolved);
      } else {
        developer.log(
          'Environment signing keys loaded but not persisted (persistEnvironmentKeys=false).',
          name: 'payload_signing_key_resolver',
          level: 800,
        );
      }
      return resolved;
    }

    if (stored != null && stored.keys.isNotEmpty) {
      return stored.copyWith(
        source: PayloadSigningConfigSource.secureStorage,
        secureStorageAvailable: _keyStore.isAvailable,
        warnings: warnings,
      );
    }

    return PayloadSigningConfig.empty(
      secureStorageAvailable: _keyStore.isAvailable,
      warnings: warnings,
    );
  }

  Future<PayloadSigningConfig?> _readStoredConfig() async {
    if (!_keyStore.isAvailable) {
      return null;
    }
    try {
      return await _keyStore.read();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to read PayloadFrame signing keys from secure storage',
        name: 'payload_signing_key_resolver',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return PayloadSigningConfig.empty(
        secureStorageAvailable: false,
        warnings: const <String>['secure_storage_read_failed'],
      );
    }
  }

  Future<void> _saveEnvironmentKeys(PayloadSigningConfig config) async {
    if (!_keyStore.isAvailable || !config.hasConfiguredSigner) {
      return;
    }
    try {
      await _keyStore.save(config);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to persist PayloadFrame signing keys to secure storage',
        name: 'payload_signing_key_resolver',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  PayloadSigningConfig _readEnvironmentConfig() {
    final warnings = <String>[];
    final keys = <String, String>{};

    final multiKeyRaw = _firstNonEmpty(<String?>[
      _environmentProvider('PAYLOAD_SIGNING_KEYS_JSON'),
      _environmentProvider('PAYLOAD_SIGNING_KEYS'),
    ]);
    if (multiKeyRaw != null) {
      final parsed = _parseMultiKeyEnvironment(multiKeyRaw);
      if (parsed == null) {
        warnings.add('payload_signing_keys_parse_failed');
      } else {
        keys.addAll(parsed);
      }
    }

    final legacyKey = _normalize(_environmentProvider('PAYLOAD_SIGNING_KEY'));
    final legacyKeyId = _normalize(_environmentProvider('PAYLOAD_SIGNING_KEY_ID'));
    if (legacyKey != null && legacyKeyId != null) {
      keys[legacyKeyId] = legacyKey;
    } else if (legacyKey != null || legacyKeyId != null) {
      warnings.add('payload_signing_legacy_key_incomplete');
    }

    final explicitActiveKeyId = _normalize(
      _environmentProvider('PAYLOAD_SIGNING_ACTIVE_KEY_ID'),
    );
    final activeKeyId = explicitActiveKeyId ?? legacyKeyId ?? _firstKeyId(keys);
    if (activeKeyId != null && !keys.containsKey(activeKeyId)) {
      warnings.add('payload_signing_active_key_not_found');
      return PayloadSigningConfig(
        keys: keys,
        source: PayloadSigningConfigSource.environment,
        secureStorageAvailable: _keyStore.isAvailable,
        warnings: warnings,
      );
    }

    return PayloadSigningConfig(
      activeKeyId: activeKeyId,
      keys: keys,
      source: PayloadSigningConfigSource.environment,
      secureStorageAvailable: _keyStore.isAvailable,
      warnings: warnings,
    );
  }

  Map<String, String>? _parseMultiKeyEnvironment(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String, String>{};
    }

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) {
          return null;
        }
        return _normalizeKeyMap(decoded);
      } on FormatException {
        return null;
      }
    }

    final parsed = <String, String>{};
    for (final pair in trimmed.split(',')) {
      final separator = pair.indexOf('=');
      if (separator <= 0 || separator == pair.length - 1) {
        return null;
      }
      final keyId = _normalize(pair.substring(0, separator));
      final secret = _normalize(pair.substring(separator + 1));
      if (keyId == null || secret == null) {
        return null;
      }
      parsed[keyId] = secret;
    }
    return parsed;
  }

  Map<String, String> _normalizeKeyMap(Map<String, dynamic> raw) {
    final normalized = <String, String>{};
    for (final entry in raw.entries) {
      final keyId = _normalize(entry.key);
      final secret = entry.value is String ? _normalize(entry.value as String) : null;
      if (keyId == null || secret == null) {
        continue;
      }
      normalized[keyId] = secret;
    }
    return normalized;
  }

  String? _firstKeyId(Map<String, String> keys) {
    if (keys.isEmpty) {
      return null;
    }
    return keys.keys.first;
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = _normalize(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
