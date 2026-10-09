import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_page.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/client_token_version_conflict_exception.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/services/i_update_maintenance_gate.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/services/client_token_secret_orchestrator.dart';
import 'package:result_dart/result_dart.dart';

class ClientTokenRepository implements IClientTokenRepository {
  ClientTokenRepository(
    this._localDataSource, {
    ITokenSecretStore? secretStore,
    Random? random,
    IUpdateMaintenanceGate? maintenanceGate,
    IAuthorizationDecisionCache? decisionCache,
    IClientTokenPolicyCache? policyCache,
    IRevokedTokenStore? revokedTokenStore,
    FeatureFlags? featureFlags,
  }) : _maintenanceGate = maintenanceGate,
       _decisionCache = decisionCache,
       _policyCache = policyCache,
       _revokedTokenStore = revokedTokenStore,
       _featureFlags = featureFlags,
       _secretOrchestrator = ClientTokenSecretOrchestrator(
         secretStore,
         _localDataSource,
       ),
       _random = random ?? Random.secure();

  final ClientTokenLocalDataSource _localDataSource;
  final ClientTokenSecretOrchestrator _secretOrchestrator;
  final Random _random;
  final IAuthorizationDecisionCache? _decisionCache;
  final IClientTokenPolicyCache? _policyCache;
  final IRevokedTokenStore? _revokedTokenStore;
  final FeatureFlags? _featureFlags;
  final IUpdateMaintenanceGate? _maintenanceGate;

  void _invalidateAuthCaches(String credentialHash) {
    if (credentialHash.isEmpty) {
      _decisionCache?.invalidateAll();
      _policyCache?.invalidateAll();
      return;
    }
    _decisionCache?.invalidateForCredentialHash(credentialHash);
    _policyCache?.invalidate(credentialHash);
  }

  void _recordRevocation(String credentialHash) {
    if (credentialHash.isNotEmpty && (_featureFlags?.enableSocketRevokedTokenInSession ?? false)) {
      _revokedTokenStore?.addCredentialHash(credentialHash);
    }
  }

  Future<Result<T>> _withAdmission<T extends Object>(Future<Result<T>> Function() action) =>
      _maintenanceGate?.run(action) ?? action();

  @override
  Future<Result<ClientTokenSummary>> getTokenById(String tokenId) async {
    return _withAdmission(() async {
      try {
        final row = await _localDataSource.findRowById(tokenId);
        if (row == null) {
          return Failure(
            domain.NotFoundFailure.withContext(
              message: 'Client token not found',
              context: {
                'operation': 'get_local_client_token_by_id',
                'token_id': tokenId,
              },
            ),
          );
        }
        return Success(await _hydrateSummary(row));
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to load client token by id',
          name: 'client_token_repository',
          error: error,
          stackTrace: stackTrace,
          level: 1000,
        );
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to load local client token',
            cause: error,
            context: {
              'operation': 'get_local_client_token_by_id',
              'token_id': tokenId,
            },
          ),
        );
      }
    });
  }

  @override
  Future<Result<ClientTokenSummary>> getTokenByHash(String tokenHash) async {
    return _withAdmission(() async {
      try {
        final row = await _localDataSource.findRowByHash(tokenHash);
        if (row == null) {
          return Failure(
            domain.NotFoundFailure.withContext(
              message: 'Client token not found',
              context: {
                'operation': 'get_local_client_token_by_hash',
                'token_hash': tokenHash,
              },
            ),
          );
        }
        return Success(await _hydrateSummary(row));
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to load client token by hash',
          name: 'client_token_repository',
          error: error,
          stackTrace: stackTrace,
          level: 1000,
        );
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to load local client token',
            cause: error,
            context: {
              'operation': 'get_local_client_token_by_hash',
              'token_hash': tokenHash,
            },
          ),
        );
      }
    });
  }

  @override
  Future<Result<ClientTokenSummary>> getTokenPolicySummaryByHash(String tokenHash) async {
    return _withAdmission(() async {
      try {
        final row = await _localDataSource.findRowByHash(tokenHash);
        if (row == null) {
          return Failure(
            domain.NotFoundFailure.withContext(
              message: 'Client token not found',
              context: {
                'operation': 'get_local_client_token_policy_by_hash',
                'token_hash': tokenHash,
              },
            ),
          );
        }
        return Success(_localDataSource.mapRowToSummaryWithoutTokenValue(row));
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to load client token policy by hash',
          name: 'client_token_repository',
          error: error,
          stackTrace: stackTrace,
          level: 1000,
        );
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to load local client token policy',
            cause: error,
            context: {
              'operation': 'get_local_client_token_policy_by_hash',
              'token_hash': tokenHash,
            },
          ),
        );
      }
    });
  }

  @override
  Future<Result<ClientTokenSecretLookup>> getTokenSecret(String tokenId) async {
    return _withAdmission(() async {
      try {
        final row = await _localDataSource.findRowById(tokenId);
        if (row == null) {
          return const Success(ClientTokenSecretLookup(tokenValue: null));
        }
        final tokenSecret = await _secretOrchestrator.readTokenSecret(row);
        final current = await _localDataSource.findRowById(tokenId);
        if (current == null ||
            current.tokenHash != row.tokenHash ||
            current.version != row.version ||
            current.createdAt != row.createdAt ||
            current.isRevoked != row.isRevoked) {
          return Failure(
            domain.ValidationFailure.withContext(
              message: 'O token foi alterado durante a leitura. Atualize a lista e tente novamente.',
              code: 'CLIENT_TOKEN_CHANGED',
              context: {'operation': 'get_local_client_token_secret', 'token_id': tokenId},
            ),
          );
        }
        return Success(ClientTokenSecretLookup(tokenValue: tokenSecret));
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to load local client token secret',
            cause: error,
            context: {
              'operation': 'get_local_client_token_secret',
              'token_id': tokenId,
            },
          ),
        );
      }
    });
  }

  @override
  Future<Result<String>> createToken(ClientTokenCreateRequest request) async {
    return _withAdmission(() async {
      try {
        final token = await _createToken(request);
        return Success(token);
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to create local client token',
            cause: error,
            context: const {'operation': 'create_local_client_token'},
          ),
        );
      }
    });
  }

  @override
  Future<Result<ClientTokenUpdateResult>> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  }) async {
    return _withAdmission(() async {
      try {
        final updateResult = await _updateToken(
          tokenId,
          request,
          expectedVersion: expectedVersion,
        );
        if (updateResult == null) {
          return Failure(
            domain.ValidationFailure(
              'Client token not found for update operation',
            ),
          );
        }
        return Success(updateResult);
      } on ClientTokenVersionConflictException catch (error) {
        final context = <String, dynamic>{
          'operation': 'update_local_client_token',
          'token_id': tokenId,
          'reason': AuthorizationContextConstants.tokenVersionConflictReason,
          'current_version': error.currentVersion,
        };
        if (expectedVersion != null) {
          context['expected_version'] = expectedVersion;
        }
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Client token was modified by another operation',
            context: context,
          ),
        );
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to update local client token',
            cause: error,
            context: {
              'operation': 'update_local_client_token',
              'token_id': tokenId,
            },
          ),
        );
      }
    });
  }

  @override
  Future<Result<List<ClientTokenSummary>>> listTokens({
    ClientTokenListQuery? query,
  }) async {
    return _withAdmission(() async {
      try {
        final tokens = await _localDataSource.listTokens(query: query);
        return Success(tokens);
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to list local client tokens',
            cause: error,
            context: const {'operation': 'list_local_client_tokens'},
          ),
        );
      }
    });
  }

  @override
  Future<Result<void>> revokeToken(String tokenId) async {
    return _withAdmission(() async {
      try {
        final revokedRow = await _localDataSource.revokeTokenRow(tokenId);
        if (revokedRow == null) {
          return Failure(
            domain.ValidationFailure(
              'Client token not found for revoke operation',
            ),
          );
        }
        _invalidateAuthCaches(revokedRow.tokenHash);
        _recordRevocation(revokedRow.tokenHash);
        return const Success(unit);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to revoke local client token',
            cause: error,
            context: {
              'operation': 'revoke_local_client_token',
              'token_id': tokenId,
            },
          ),
        );
      }
    });
  }

  @override
  Future<Result<ClientTokenPage>> listTokenPage({required ClientTokenListQuery query}) {
    return _withAdmission(() async {
      final size = query.pageSize ?? ClientTokenListQuery.defaultPageSize;
      if ((query.page ?? 1) < 1 || !ClientTokenListQuery.supportedPageSizes.contains(size)) {
        return Failure(domain.ValidationFailure('Invalid client token page'));
      }
      try {
        return Success(await _localDataSource.listTokenPage(query: query));
      } on domain.Failure catch (failure) {
        return Failure(failure);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Não foi possível carregar a página de tokens. Tente atualizar a lista.',
            cause: error,
            context: const {'operation': 'list_client_token_page'},
          ),
        );
      }
    });
  }

  @override
  Future<Result<int>> countActiveTokens() {
    return _withAdmission(() async {
      try {
        return Success(await _localDataSource.countActiveTokens());
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Não foi possível atualizar a contagem de tokens ativos.',
            cause: error,
            context: const {'operation': 'count_active_client_tokens'},
          ),
        );
      }
    });
  }

  @override
  Future<Result<void>> deleteToken(String tokenId) async {
    return _withAdmission(() async {
      try {
        final deletedRow = await _localDataSource.deleteToken(tokenId);
        if (deletedRow == null) {
          return Failure(
            domain.ValidationFailure(
              'Client token not found for delete operation',
            ),
          );
        }
        _invalidateAuthCaches(deletedRow.tokenHash);
        await _secretOrchestrator.deleteStoredSecretsBestEffort(
          tokenId: tokenId,
          tokenHash: deletedRow.tokenHash,
        );
        return const Success(unit);
      } on Exception catch (error) {
        return Failure(
          domain.DatabaseFailure.withContext(
            message: 'Failed to delete local client token',
            cause: error,
            context: {
              'operation': 'delete_local_client_token',
              'token_id': tokenId,
            },
          ),
        );
      }
    });
  }

  Future<void> replaceTokens(List<ClientTokenSummary> tokens) async {
    Future<void> replace() async {
      if (tokens.isEmpty) {
        return;
      }

      final previousRowsById = await _localDataSource.loadAllRowsById();
      final rows = tokens
          .map(
            (token) => (
              summary: token,
              tokenHash: fallbackStoredClientTokenHash(
                tokenId: token.id,
                tokenValue: token.tokenValue,
              ),
              persistedTokenValue: _secretOrchestrator.persistedTokenValueForStorage(
                token.tokenValue,
              ),
            ),
          )
          .toList();

      final previousHashes = previousRowsById.values.map((row) => row.tokenHash).toSet();
      final newKeys = <String>{};
      try {
        for (final row in rows) {
          final value = row.summary.tokenValue?.trim();
          if (value == null || value.isEmpty) {
            continue;
          }
          if (!previousHashes.contains(row.tokenHash)) {
            newKeys.add(row.tokenHash);
          }
          (await _secretOrchestrator.saveRequiredSecret(row.tokenHash, value)).getOrThrow();
        }
        await _localDataSource.replaceTokenRows(rows: rows);
      } on Exception {
        for (final key in newKeys) {
          await _secretOrchestrator.deleteSecretBestEffort(key);
        }
        rethrow;
      }
      _decisionCache?.invalidateAll();
      _policyCache?.invalidateAll();
      for (final row in rows) {
        if (row.summary.isRevoked) _recordRevocation(row.tokenHash);
      }
      await _secretOrchestrator.syncSecretsForReplacement(
        tokens: tokens,
        previousRowsById: previousRowsById,
      );
    }

    return _maintenanceGate?.runValue(replace) ?? replace();
  }

  String hashTokenForLookup(String token) => hashStoredClientToken(token);

  Future<String> _createToken(ClientTokenCreateRequest request) async {
    final now = DateTime.now().toUtc();
    final tokenId = buildClientTokenId(_random);
    final opaqueToken = generateOpaqueClientToken(_random);
    final tokenHash = hashStoredClientToken(opaqueToken);
    final saved = await _secretOrchestrator.saveRequiredSecret(tokenHash, opaqueToken);
    if (saved.isError()) {
      await _secretOrchestrator.deleteSecretBestEffort(tokenHash);
      throw saved.exceptionOrNull()!;
    }
    final summary = ClientTokenSummary(
      id: tokenId,
      clientId: request.clientId.trim(),
      name: request.name.trim(),
      createdAt: now,
      isRevoked: false,
      tokenValue: opaqueToken,
      allTables: request.allTables,
      allViews: request.allViews,
      globalPermissions: request.effectiveGlobalPermissions,
      rules: request.effectiveRules,
      agentId: normalizeClientTokenAgentId(request.agentId),
      payload: request.payload,
    );

    try {
      await _localDataSource.insertToken(
        summary: summary,
        tokenHash: tokenHash,
        persistedTokenValue: _secretOrchestrator.persistedTokenValueForStorage(opaqueToken),
        syncedAt: now,
      );
    } on Exception {
      await _secretOrchestrator.deleteSecretBestEffort(tokenHash);
      rethrow;
    }

    _invalidateAuthCaches(tokenHash);
    return opaqueToken;
  }

  Future<ClientTokenUpdateResult?> _updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  }) async {
    final current = await _localDataSource.findRowById(tokenId);
    if (current == null) {
      return null;
    }

    if (expectedVersion != null && current.version != expectedVersion) {
      throw ClientTokenVersionConflictException(
        currentVersion: current.version,
      );
    }

    final currentSummary = _localDataSource.mapRowToSummaryWithoutTokenValue(current);
    final policyChanged = request.changesAuthorizationPolicyFrom(currentSummary);
    final metadataChanged = request.changesMetadataFrom(currentSummary);

    if (!policyChanged && !metadataChanged) {
      return ClientTokenUpdateResult(
        outcome: ClientTokenUpdateOutcome.unchanged,
        version: current.version,
        updatedAt: current.updatedAt ?? current.createdAt,
      );
    }

    final shouldRotateToken = policyChanged;
    final nextVersion = current.version + 1;
    final now = DateTime.now().toUtc();

    final String? newTokenValue;
    final String? newTokenHash;
    if (shouldRotateToken) {
      newTokenValue = generateOpaqueClientToken(_random);
      newTokenHash = hashStoredClientToken(newTokenValue);
      final saved = await _secretOrchestrator.saveRequiredSecret(newTokenHash, newTokenValue);
      if (saved.isError()) {
        await _secretOrchestrator.deleteSecretBestEffort(newTokenHash);
        throw saved.exceptionOrNull()!;
      }
    } else {
      newTokenValue = null;
      newTokenHash = null;
    }

    try {
      final affectedRows = await _localDataSource.applyTokenUpdate(
        tokenId: tokenId,
        expectedVersion: current.version,
        companion: ClientTokenCacheTableCompanion(
          clientId: Value(request.normalizedClientId),
          name: Value(request.normalizedName),
          agentId: Value(request.normalizedAgentId),
          tokenHash: shouldRotateToken ? Value(newTokenHash!) : const Value.absent(),
          tokenValue: shouldRotateToken
              ? Value(_secretOrchestrator.persistedTokenValueForStorage(newTokenValue))
              : const Value.absent(),
          payloadJson: Value(jsonEncode(request.payload)),
          allTables: Value(request.allTables),
          allViews: Value(request.allViews),
          allPermissions: Value(request.allPermissions),
          globalPermissionsJson: Value(
            jsonEncode(request.effectiveGlobalPermissions.toJson()),
          ),
          rulesJson: Value(
            jsonEncode(
              request.effectiveRules.map((rule) => rule.toJson()).toList(),
            ),
          ),
          version: Value(nextVersion),
          updatedAt: Value(now),
          syncedAt: Value(now),
        ),
      );
      if (affectedRows == 0) {
        final latest = await _localDataSource.findRowById(tokenId);
        throw ClientTokenVersionConflictException(
          currentVersion: latest?.version ?? current.version,
        );
      }
    } on Exception {
      if (shouldRotateToken) {
        await _secretOrchestrator.deleteSecretBestEffort(newTokenHash!);
      }
      rethrow;
    }

    // Policy introspection and cached denials also contain mutable identity metadata.
    _invalidateAuthCaches(current.tokenHash);
    if (shouldRotateToken) {
      _invalidateAuthCaches(newTokenHash!);
      await _secretOrchestrator.deleteStoredSecretsBestEffort(
        tokenId: tokenId,
        tokenHash: current.tokenHash,
      );
    }

    return ClientTokenUpdateResult(
      outcome: shouldRotateToken ? ClientTokenUpdateOutcome.rotated : ClientTokenUpdateOutcome.metadataOnly,
      tokenValue: newTokenValue,
      version: nextVersion,
      updatedAt: now,
    );
  }

  Future<ClientTokenSummary> _hydrateSummary(ClientTokenCacheData row) async {
    final summary = _localDataSource.mapRowToSummaryWithoutTokenValue(row);
    final tokenValue = await _secretOrchestrator.resolveTokenValue(row);
    return ClientTokenSummary(
      id: summary.id,
      clientId: summary.clientId,
      name: summary.name,
      createdAt: summary.createdAt,
      isRevoked: summary.isRevoked,
      agentId: summary.agentId,
      tokenValue: tokenValue,
      version: summary.version,
      updatedAt: summary.updatedAt,
      payload: summary.payload,
      allTables: summary.allTables,
      allViews: summary.allViews,
      globalPermissions: summary.globalPermissions,
      rules: summary.rules,
    );
  }
}
