import 'dart:collection';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_key_resolver.dart';

class FlutterSecurePayloadSigningKeyStore implements PayloadSigningKeyStore {
  FlutterSecurePayloadSigningKeyStore({
    FlutterSecureStorage? secureStorage,
    this.keyPrefix = 'payload_signing_',
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  final String keyPrefix;

  String get _keysJsonKey => '${keyPrefix}keys_json';
  String get _activeKeyIdKey => '${keyPrefix}active_key_id';

  @override
  bool get isAvailable => true;

  @override
  Future<PayloadSigningConfig?> read() async {
    final rawKeys = await _secureStorage.read(key: _keysJsonKey);
    if (rawKeys == null || rawKeys.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawKeys);
      if (decoded is! Map<String, dynamic>) {
        return PayloadSigningConfig.empty(
          warnings: const <String>['payload_signing_secure_keys_invalid_root'],
        );
      }
      final keys = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.value is String && entry.value.toString().trim().isNotEmpty) {
          keys[entry.key] = entry.value as String;
        }
      }
      final activeKeyId = await _secureStorage.read(key: _activeKeyIdKey);
      return PayloadSigningConfig(
        activeKeyId: activeKeyId,
        keys: keys,
        source: PayloadSigningConfigSource.secureStorage,
      );
    } on FormatException {
      return PayloadSigningConfig.empty(
        warnings: const <String>['payload_signing_secure_keys_parse_failed'],
      );
    }
  }

  @override
  Future<void> save(PayloadSigningConfig config) async {
    if (config.keys.isEmpty) {
      await _secureStorage.delete(key: _keysJsonKey);
      await _secureStorage.delete(key: _activeKeyIdKey);
      return;
    }

    final sortedKeys = SplayTreeMap<String, String>.from(config.keys);
    await _secureStorage.write(
      key: _keysJsonKey,
      value: jsonEncode(sortedKeys),
    );

    final activeKeyId = config.activeKeyId;
    if (activeKeyId == null || activeKeyId.isEmpty) {
      await _secureStorage.delete(key: _activeKeyIdKey);
    } else {
      await _secureStorage.write(key: _activeKeyIdKey, value: activeKeyId);
    }
  }
}
