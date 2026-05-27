import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class ClientTokenProvider extends ChangeNotifier {
  ClientTokenProvider(
    this._createClientToken,
    this._updateClientToken,
    this._listClientTokens,
    this._getClientTokenSecret,
    this._revokeClientToken,
    this._deleteClientToken, {
    ITokenAuditStore? tokenAuditStore,
  }) : _tokenAuditStore = tokenAuditStore;

  final CreateClientToken _createClientToken;
  final UpdateClientToken _updateClientToken;
  final ListClientTokens _listClientTokens;
  final GetClientTokenSecret _getClientTokenSecret;
  final RevokeClientToken _revokeClientToken;
  final DeleteClientToken _deleteClientToken;
  final ITokenAuditStore? _tokenAuditStore;

  List<ClientTokenSummary> _tokens = const <ClientTokenSummary>[];
  bool _isLoading = false;
  bool _isCreating = false;
  bool _isRevoking = false;
  bool _isDeleting = false;
  bool _isCopyingTokenSecret = false;
  String? _revokingTokenId;
  String? _deletingTokenId;
  String? _copyingTokenSecretId;
  String _error = '';
  String? _lastCreatedToken;
  ClientTokenUpdateOutcome? _lastUpdateOutcome;
  bool _hasLoaded = false;
  ClientTokenListQuery _lastListQuery = const ClientTokenListQuery();
  int _loadGeneration = 0;

  List<ClientTokenSummary> get tokens => _tokens;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isRevoking => _isRevoking;
  bool get isDeleting => _isDeleting;
  bool get isCopyingTokenSecret => _isCopyingTokenSecret;
  String? get revokingTokenId => _revokingTokenId;
  String? get deletingTokenId => _deletingTokenId;
  String? get copyingTokenSecretId => _copyingTokenSecretId;
  String get error => _error;
  String? get lastCreatedToken => _lastCreatedToken;

  /// Outcome of the most recent successful update. `null` outside of a
  /// recently-completed edit cycle. Consumed by the UI to decide between
  /// "rotated", "metadata only" and "no change" feedback.
  ClientTokenUpdateOutcome? get lastUpdateOutcome => _lastUpdateOutcome;
  bool get hasLoaded => _hasLoaded;
  bool get isListMutationInProgress => _isRevoking || _isDeleting;
  bool get isTokenMutationInProgress => _isCreating || _isRevoking || _isDeleting;

  Future<bool> loadTokens({
    bool silent = false,
    ClientTokenListQuery? query,
  }) async {
    final effectiveQuery = query ?? _lastListQuery;
    _lastListQuery = effectiveQuery;
    final generation = ++_loadGeneration;

    _isLoading = true;
    _error = '';
    notifyListeners();

    final result = await _listClientTokens(query: effectiveQuery);

    if (generation != _loadGeneration) {
      return false;
    }

    var isSuccess = false;
    result.fold(
      (tokens) {
        _tokens = tokens;
        _error = '';
        _hasLoaded = true;
        isSuccess = true;
      },
      (failure) {
        _error = failure.toDisplayMessage();
      },
    );

    _isLoading = false;
    notifyListeners();

    return isSuccess;
  }

  Future<bool> createToken(
    ClientTokenCreateRequest request, {
    bool refreshTokens = true,
  }) async {
    _isCreating = true;
    _error = '';
    _lastCreatedToken = null;
    notifyListeners();

    final result = await _createClientToken(request);
    var isSuccess = false;

    await result.fold(
      (token) async {
        _lastCreatedToken = token;
        _error = '';
        isSuccess = true;
        if (refreshTokens) {
          await loadTokens(silent: true);
        }
      },
      (failure) async {
        _error = failure.toDisplayMessage();
      },
    );

    _isCreating = false;
    notifyListeners();
    return isSuccess;
  }

  Future<bool> revokeToken(String tokenId) async {
    if (isListMutationInProgress) {
      return false;
    }
    _isRevoking = true;
    _revokingTokenId = tokenId;
    _error = '';
    notifyListeners();

    final result = await _revokeClientToken(tokenId);
    var isSuccess = false;

    await result.fold(
      (_) async {
        _error = '';
        isSuccess = true;
        _markTokenRevokedInMemory(tokenId);
      },
      (failure) async {
        _error = failure.toDisplayMessage();
      },
    );

    _isRevoking = false;
    _revokingTokenId = null;
    notifyListeners();
    return isSuccess;
  }

  Future<bool> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    bool refreshTokens = true,
    int? expectedVersion,
  }) async {
    _isCreating = true;
    _error = '';
    _lastCreatedToken = null;
    _lastUpdateOutcome = null;
    notifyListeners();

    final result = await _updateClientToken(
      tokenId,
      request,
      expectedVersion: expectedVersion,
    );
    var isSuccess = false;

    await result.fold(
      (updateResult) async {
        _error = '';
        _lastUpdateOutcome = updateResult.outcome;
        _lastCreatedToken = updateResult.didRotateToken ? updateResult.tokenValue : null;
        isSuccess = true;
        if (updateResult.outcome == ClientTokenUpdateOutcome.unchanged) {
          // Persisted state already matched the request; nothing in memory
          // needs to change either.
          return;
        }
        final patched = _applyUpdatedTokenInMemory(
          tokenId: tokenId,
          request: request,
          nextVersion: updateResult.version,
          updatedAt: updateResult.updatedAt,
          didRotateToken: updateResult.didRotateToken,
        );
        if (refreshTokens && !patched) {
          await loadTokens(silent: true);
        }
      },
      (failure) async {
        _error = failure.toDisplayMessage();
      },
    );

    _isCreating = false;
    notifyListeners();
    return isSuccess;
  }

  void clearLastUpdateOutcome() {
    if (_lastUpdateOutcome == null) {
      return;
    }
    _lastUpdateOutcome = null;
    notifyListeners();
  }

  bool isRevokingToken(String tokenId) {
    return _isRevoking && _revokingTokenId == tokenId;
  }

  Future<bool> deleteToken(String tokenId) async {
    if (isListMutationInProgress) {
      return false;
    }
    _isDeleting = true;
    _deletingTokenId = tokenId;
    _error = '';
    notifyListeners();

    final result = await _deleteClientToken(tokenId);
    var isSuccess = false;

    await result.fold(
      (_) async {
        _error = '';
        isSuccess = true;
        _tokens = _tokens.where((token) => token.id != tokenId).toList();
      },
      (failure) async {
        _error = failure.toDisplayMessage();
      },
    );

    _isDeleting = false;
    _deletingTokenId = null;
    notifyListeners();
    return isSuccess;
  }

  bool isDeletingToken(String tokenId) {
    return _isDeleting && _deletingTokenId == tokenId;
  }

  bool isCopyingTokenSecretFor(String tokenId) {
    return _isCopyingTokenSecret && _copyingTokenSecretId == tokenId;
  }

  Future<Result<ClientTokenSecretLookup>> getTokenSecret(String tokenId) async {
    if (_isCopyingTokenSecret) {
      return Failure(
        domain.ValidationFailure('Client token secret copy is already in progress'),
      );
    }

    _isCopyingTokenSecret = true;
    _copyingTokenSecretId = tokenId;
    notifyListeners();

    try {
      return await _getClientTokenSecret(tokenId);
    } finally {
      _isCopyingTokenSecret = false;
      _copyingTokenSecretId = null;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error.isEmpty) {
      return;
    }
    _error = '';
    notifyListeners();
  }

  void clearLastCreatedToken() {
    if (_lastCreatedToken == null) {
      return;
    }
    _lastCreatedToken = null;
    notifyListeners();
  }

  Future<void> recordCopiedToken({
    required String tokenId,
    required String clientId,
  }) async {
    final auditStore = _tokenAuditStore;
    if (auditStore == null) {
      return;
    }
    try {
      await auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.copy,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
          clientId: clientId,
        ),
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Token copy audit record failed (must not impact UI flow)',
        name: 'client_token_provider',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  bool _applyUpdatedTokenInMemory({
    required String tokenId,
    required ClientTokenCreateRequest request,
    required int nextVersion,
    required DateTime updatedAt,
    required bool didRotateToken,
  }) {
    final index = _tokens.indexWhere((token) => token.id == tokenId);
    if (index < 0) {
      return false;
    }

    final current = _tokens[index];
    final agentId = request.agentId?.trim();
    // When the token did not rotate, keep the previously cached tokenValue
    // (typically null on list views). When it rotated, force a re-fetch by
    // clearing the in-memory copy so the UI never displays a stale secret.
    final next = current.copyWith(
      clientId: request.clientId.trim(),
      name: request.name.trim(),
      agentId: agentId == null || agentId.isEmpty ? null : agentId,
      payload: request.payload,
      allTables: request.allTables,
      allViews: request.allViews,
      globalPermissions: request.effectiveGlobalPermissions,
      rules: request.effectiveRules,
      tokenValue: didRotateToken ? null : current.tokenValue,
      version: nextVersion,
      updatedAt: updatedAt,
    );

    final mutable = List<ClientTokenSummary>.from(_tokens);
    mutable[index] = next;
    _tokens = _applyQueryToTokens(mutable, _lastListQuery);
    return true;
  }

  void _markTokenRevokedInMemory(String tokenId) {
    final index = _tokens.indexWhere((token) => token.id == tokenId);
    if (index < 0) {
      return;
    }
    final current = _tokens[index];
    final mutable = List<ClientTokenSummary>.from(_tokens);
    mutable[index] = current.copyWith(
      isRevoked: true,
      version: current.version + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    _tokens = _applyQueryToTokens(mutable, _lastListQuery);
  }

  List<ClientTokenSummary> _applyQueryToTokens(
    List<ClientTokenSummary> tokens,
    ClientTokenListQuery query,
  ) {
    final normalizedClientFilter = query.clientIdContains.trim().toLowerCase();

    final filtered = tokens.where((token) {
      if (normalizedClientFilter.isNotEmpty) {
        final matchesClientId = token.clientId.toLowerCase().contains(
          normalizedClientFilter,
        );
        final matchesName = token.name.toLowerCase().contains(
          normalizedClientFilter,
        );
        if (!matchesClientId && !matchesName) {
          return false;
        }
      }

      return switch (query.status) {
        ClientTokenStatusFilter.all => true,
        ClientTokenStatusFilter.active => !token.isRevoked,
        ClientTokenStatusFilter.revoked => token.isRevoked,
      };
    }).toList();

    filtered.sort((left, right) {
      final bySelectedSort = switch (query.sort) {
        ClientTokenSortOption.newest => right.createdAt.compareTo(left.createdAt),
        ClientTokenSortOption.oldest => left.createdAt.compareTo(right.createdAt),
        ClientTokenSortOption.clientAsc => left.clientId.toLowerCase().compareTo(
          right.clientId.toLowerCase(),
        ),
        ClientTokenSortOption.clientDesc => right.clientId.toLowerCase().compareTo(
          left.clientId.toLowerCase(),
        ),
      };

      if (bySelectedSort != 0) {
        return bySelectedSort;
      }

      return right.createdAt.compareTo(left.createdAt);
    });

    if (!query.hasPagination) {
      return filtered;
    }

    final start = query.offset.clamp(0, filtered.length);
    final end = (start + query.pageSize!).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }
}
