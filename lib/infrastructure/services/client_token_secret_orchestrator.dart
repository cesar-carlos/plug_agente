import 'dart:developer' as developer;

import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class ClientTokenSecretOrchestrator {
  ClientTokenSecretOrchestrator(this._secretStore, this._dataSource);

  final ITokenSecretStore? _secretStore;
  final ClientTokenLocalDataSource _dataSource;

  static const secureStorageMarker = '__secure_storage__';

  bool get secureStorageEnabled => _secretStore?.isAvailable ?? false;

  String? persistedTokenValueForStorage(String? tokenValue) {
    if (tokenValue == null || tokenValue.isEmpty) {
      return null;
    }
    return secureStorageEnabled ? secureStorageMarker : tokenValue;
  }

  Future<String?> resolveTokenValue(ClientTokenCacheData row) {
    return _resolveTokenValue(
      tokenId: row.id,
      tokenHash: row.tokenHash,
      persistedTokenValue: row.tokenValue,
    );
  }

  Future<String?> readTokenSecret(ClientTokenCacheData row) {
    return resolveTokenValue(row);
  }

  Future<bool> saveSecretBestEffort(String secretKey, String tokenValue) async {
    final secretStore = _secretStore;
    if (secretStore == null || !secretStore.isAvailable) {
      return false;
    }
    try {
      await secretStore.saveSecret(secretKey, tokenValue);
      return true;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Secret persistence failed (must not block token operations)',
        name: 'client_token_secret_orchestrator',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> deleteSecretBestEffort(String secretKey) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return;
    }
    try {
      await secretStore.deleteSecret(secretKey);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Secret delete failed (best effort cleanup)',
        name: 'client_token_secret_orchestrator',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> deleteStoredSecretsBestEffort({
    required String tokenId,
    required String tokenHash,
  }) async {
    await deleteSecretBestEffort(tokenHash);
    await deleteSecretBestEffort(tokenId);
  }

  Future<void> syncSecretsForReplacement({
    required List<ClientTokenSummary> tokens,
    required Map<String, ClientTokenCacheData> previousRowsById,
  }) async {
    for (final token in tokens) {
      final previousRow = previousRowsById[token.id];
      final tokenValue = token.tokenValue?.trim();
      if (tokenValue == null || tokenValue.isEmpty) {
        await deleteStoredSecretsBestEffort(
          tokenId: token.id,
          tokenHash: fallbackStoredClientTokenHash(
            tokenId: token.id,
            tokenValue: token.tokenValue,
          ),
        );
        if (previousRow != null) {
          await deleteSecretBestEffort(previousRow.tokenHash);
        }
        continue;
      }
      final tokenHash = fallbackStoredClientTokenHash(
        tokenId: token.id,
        tokenValue: tokenValue,
      );
      await saveSecretBestEffort(tokenHash, tokenValue);
      await deleteSecretBestEffort(token.id);
      if (previousRow != null && previousRow.tokenHash != tokenHash) {
        await deleteSecretBestEffort(previousRow.tokenHash);
      }
    }
  }

  Future<String?> _resolveTokenValue({
    required String tokenId,
    required String tokenHash,
    required String? persistedTokenValue,
  }) async {
    if (secureStorageEnabled) {
      final secret = await _readSecretBestEffort(tokenHash);
      if (secret != null && secret.isNotEmpty) {
        return secret;
      }
      final legacySecret = await _readSecretBestEffort(tokenId);
      if (legacySecret != null && legacySecret.isNotEmpty) {
        await _migrateLegacyTokenValueToSecretStore(
          tokenId: tokenId,
          tokenHash: tokenHash,
          tokenValue: legacySecret,
        );
        return legacySecret;
      }
    }

    if (persistedTokenValue == null || persistedTokenValue.isEmpty) {
      return null;
    }
    if (persistedTokenValue == secureStorageMarker) {
      return null;
    }

    await _migrateLegacyTokenValueToSecretStore(
      tokenId: tokenId,
      tokenHash: tokenHash,
      tokenValue: persistedTokenValue,
    );
    return persistedTokenValue;
  }

  Future<void> _migrateLegacyTokenValueToSecretStore({
    required String tokenId,
    required String tokenHash,
    required String tokenValue,
  }) async {
    if (!secureStorageEnabled) {
      return;
    }
    final didSave = await saveSecretBestEffort(tokenHash, tokenValue);
    if (!didSave) {
      return;
    }
    try {
      await _dataSource.updatePersistedTokenValue(
        tokenId: tokenId,
        tokenValue: secureStorageMarker,
      );
      await deleteSecretBestEffort(tokenId);
      developer.log(
        'Migrated legacy client token secret to hash-based storage (token_id=$tokenId)',
        name: 'client_token_secret_orchestrator',
        level: 800,
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Token migration to secret store failed (best effort)',
        name: 'client_token_secret_orchestrator',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String?> _readSecretBestEffort(String secretKey) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return null;
    }
    try {
      return await secretStore.readSecret(secretKey);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Secret read failed',
        name: 'client_token_secret_orchestrator',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
