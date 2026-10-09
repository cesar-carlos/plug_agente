import 'dart:developer' as developer;

import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';

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
    return secureStorageMarker;
  }

  Future<Result<void>> saveRequiredSecret(String secretKey, String tokenValue) async {
    if (!secureStorageEnabled) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'O armazenamento seguro está indisponível. Repare o acesso antes de criar ou rotacionar tokens.',
          code: 'CLIENT_TOKEN_STORAGE_UNAVAILABLE',
          context: const {'operation': 'save_client_token_secret'},
        ),
      );
    }
    try {
      await _secretStore!.saveSecret(secretKey, tokenValue);
      if (await _secretStore.readSecret(secretKey) != tokenValue) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message:
                'Não foi possível confirmar o segredo do token. Tente novamente após reparar o armazenamento seguro.',
            code: 'CLIENT_TOKEN_STORAGE_UNCONFIRMED',
            context: const {'operation': 'verify_client_token_secret'},
          ),
        );
      }
      return const Success(unit);
    } on Exception catch (error) {
      // Platform errors may contain the credential; expose only safe context.
      return Failure(
        domain.ConfigurationFailure.withContext(
          message:
              'Não foi possível gravar e confirmar o segredo do token. Verifique o armazenamento seguro e tente novamente.',
          code: 'CLIENT_TOKEN_STORAGE_FAILED',
          context: {'operation': 'save_client_token_secret', 'cause_type': error.runtimeType.toString()},
        ),
      );
    }
  }

  Future<String?> resolveTokenValue(ClientTokenCacheData row) {
    return _resolveTokenValue(
      tokenId: row.id,
      tokenHash: row.tokenHash,
      version: row.version,
      persistedTokenValue: row.tokenValue,
    );
  }

  Future<String?> readTokenSecret(ClientTokenCacheData row) {
    return resolveTokenValue(row);
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
        error: error.runtimeType,
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
      await deleteSecretBestEffort(token.id);
      if (previousRow != null && previousRow.tokenHash != tokenHash) {
        await deleteSecretBestEffort(previousRow.tokenHash);
      }
    }
  }

  Future<String?> _resolveTokenValue({
    required String tokenId,
    required String tokenHash,
    required int version,
    required String? persistedTokenValue,
  }) async {
    if (secureStorageEnabled) {
      final secret = await _readSecretBestEffort(tokenHash);
      if (secret != null && secret.isNotEmpty) {
        _validateSecretHash(tokenId, tokenHash, secret);
        return secret;
      }
      final legacySecret = await _readSecretBestEffort(tokenId);
      if (legacySecret != null && legacySecret.isNotEmpty) {
        _validateSecretHash(tokenId, tokenHash, legacySecret);
        await _migrateLegacyTokenValueToSecretStore(
          tokenId: tokenId,
          tokenHash: tokenHash,
          version: version,
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

    _validateSecretHash(tokenId, tokenHash, persistedTokenValue);
    await _migrateLegacyTokenValueToSecretStore(
      tokenId: tokenId,
      tokenHash: tokenHash,
      version: version,
      tokenValue: persistedTokenValue,
    );
    return persistedTokenValue;
  }

  void _validateSecretHash(String tokenId, String tokenHash, String tokenValue) {
    if (hashStoredClientToken(tokenValue) == tokenHash) return;
    throw domain.ConfigurationFailure.withContext(
      message: 'O segredo salvo não corresponde ao token atual. Crie outro token para recuperar a credencial.',
      code: 'CLIENT_TOKEN_SECRET_MISMATCH',
      context: {'operation': 'verify_client_token_secret', 'token_id': tokenId},
    );
  }

  Future<void> _cleanupUnreferencedSecret(String tokenHash) async {
    try {
      await _dataSource.runIfTokenHashUnreferenced(tokenHash, () => deleteSecretBestEffort(tokenHash));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Secret cleanup ownership check failed; preserving secret',
        name: 'client_token_secret_orchestrator',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _migrateLegacyTokenValueToSecretStore({
    required String tokenId,
    required String tokenHash,
    required String tokenValue,
    required int version,
  }) async {
    if (!secureStorageEnabled) {
      return;
    }
    final saved = await saveRequiredSecret(tokenHash, tokenValue);
    if (saved.isError()) {
      (saved.exceptionOrNull()! as domain.Failure).log();
      await _cleanupUnreferencedSecret(tokenHash);
      return;
    }
    try {
      final affectedRows = await _dataSource.updatePersistedTokenValue(
        tokenId: tokenId,
        tokenValue: secureStorageMarker,
        expectedTokenHash: tokenHash,
        expectedVersion: version,
      );
      if (affectedRows == 0) {
        await _cleanupUnreferencedSecret(tokenHash);
        developer.log(
          'Legacy secret migration superseded by a token change (token_id=$tokenId)',
          name: 'client_token_secret_orchestrator',
        );
        return;
      }
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
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      await _cleanupUnreferencedSecret(tokenHash);
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
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
