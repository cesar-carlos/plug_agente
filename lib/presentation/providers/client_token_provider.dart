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
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/presentation/providers/presentation_error_state.dart';
import 'package:plug_agente/presentation/providers/presentation_operation_failures.dart';
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
  PresentationErrorState? _errorState;
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
  PresentationErrorState? get errorState => _errorState;
  String get error => _errorState?.message ?? '';
  bool get errorCanRetry => _errorState?.canRetry ?? false;
  String? get lastCreatedToken => _lastCreatedToken;

  /// Outcome of the most recent successful update. `null` outside of a
  /// recently-completed edit cycle. Consumed by the UI to decide between
  /// "rotated", "metadata only" and "no change" feedback.
  ClientTokenUpdateOutcome? get lastUpdateOutcome => _lastUpdateOutcome;
  bool get hasLoaded => _hasLoaded;
  bool get isListMutationInProgress => _isRevoking || _isDeleting;
  bool get isTokenMutationInProgress => _isCreating || _isRevoking || _isDeleting;

  Future<Result<void>> loadTokens({
    bool silent = false,
    ClientTokenListQuery? query,
  }) async {
    final effectiveQuery = query ?? _lastListQuery;
    _lastListQuery = effectiveQuery;
    final generation = ++_loadGeneration;

    _isLoading = true;
    _clearErrorState();
    notifyListeners();

    final result = await _listClientTokens(query: effectiveQuery);

    if (generation != _loadGeneration) {
      _isLoading = false;
      notifyListeners();
      return Failure(PresentationOperationFailures.superseded);
    }

    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      _applyFailure(failure);
      _isLoading = false;
      notifyListeners();
      return Failure(failure);
    }

    _tokens = result.getOrThrow();
    _clearErrorState();
    _hasLoaded = true;
    _isLoading = false;
    notifyListeners();
    return const Success(unit);
  }

  Future<Result<void>> createToken(
    ClientTokenCreateRequest request, {
    bool refreshTokens = true,
  }) async {
    _isCreating = true;
    _clearErrorState();
    _lastCreatedToken = null;
    notifyListeners();

    final result = await _createClientToken(request);

    late final Result<void> outcome;
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      _applyFailure(failure);
      outcome = Failure(failure);
    } else {
      _lastCreatedToken = result.getOrThrow();
      _clearErrorState();
      outcome = refreshTokens ? await loadTokens(silent: true) : const Success(unit);
    }

    _isCreating = false;
    notifyListeners();
    return outcome;
  }

  Future<Result<void>> revokeToken(String tokenId) async {
    if (isListMutationInProgress) {
      return Failure(PresentationOperationFailures.operationBlocked);
    }
    _isRevoking = true;
    _revokingTokenId = tokenId;
    _clearErrorState();
    notifyListeners();

    final result = await _revokeClientToken(tokenId);

    late final Result<void> outcome;
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      _applyFailure(failure);
      outcome = Failure(failure);
    } else {
      _clearErrorState();
      _markTokenRevokedInMemory(tokenId);
      outcome = const Success(unit);
    }

    _isRevoking = false;
    _revokingTokenId = null;
    notifyListeners();
    return outcome;
  }

  Future<Result<void>> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    bool refreshTokens = true,
    int? expectedVersion,
  }) async {
    _isCreating = true;
    _clearErrorState();
    _lastCreatedToken = null;
    _lastUpdateOutcome = null;
    notifyListeners();

    final result = await _updateClientToken(
      tokenId,
      request,
      expectedVersion: expectedVersion,
    );

    late final Result<void> outcome;
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      _applyFailure(failure);
      outcome = Failure(failure);
    } else {
      final updateResult = result.getOrThrow();
      _clearErrorState();
      _lastUpdateOutcome = updateResult.outcome;
      _lastCreatedToken = updateResult.didRotateToken ? updateResult.tokenValue : null;
      if (updateResult.outcome == ClientTokenUpdateOutcome.unchanged) {
        outcome = const Success(unit);
      } else {
        final patched = _applyUpdatedTokenInMemory(
          tokenId: tokenId,
          request: request,
          nextVersion: updateResult.version,
          updatedAt: updateResult.updatedAt,
          didRotateToken: updateResult.didRotateToken,
        );
        outcome = refreshTokens && !patched ? await loadTokens(silent: true) : const Success(unit);
      }
    }

    _isCreating = false;
    notifyListeners();
    return outcome;
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

  Future<Result<void>> deleteToken(String tokenId) async {
    if (isListMutationInProgress) {
      return Failure(PresentationOperationFailures.operationBlocked);
    }
    _isDeleting = true;
    _deletingTokenId = tokenId;
    _clearErrorState();
    notifyListeners();

    final result = await _deleteClientToken(tokenId);

    late final Result<void> outcome;
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      _applyFailure(failure);
      outcome = Failure(failure);
    } else {
      _clearErrorState();
      _tokens = _tokens.where((token) => token.id != tokenId).toList();
      outcome = const Success(unit);
    }

    _isDeleting = false;
    _deletingTokenId = null;
    notifyListeners();
    return outcome;
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
    if (_errorState == null) {
      return;
    }
    _clearErrorState();
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

  void _applyFailure(Object failure) {
    _errorState = PresentationErrorState.fromFailure(failure);
  }

  void _clearErrorState() {
    _errorState = null;
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
