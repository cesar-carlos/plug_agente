import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/count_active_client_tokens.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/list_client_token_page.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/presentation/providers/presentation_error_state.dart';
import 'package:plug_agente/presentation/providers/presentation_operation_failures.dart';
import 'package:result_dart/result_dart.dart';

enum _TokenMutation { save, revoke, delete }

class ClientTokenProvider extends ChangeNotifier {
  ClientTokenProvider(
    this._createClientToken,
    this._updateClientToken,
    this._listClientTokenPage,
    this._getClientTokenSecret,
    this._revokeClientToken,
    this._deleteClientToken, {
    required CountActiveClientTokens countActiveClientTokens,
    ITokenAuditStore? tokenAuditStore,
  }) : _countActiveClientTokens = countActiveClientTokens,
       _tokenAuditStore = tokenAuditStore;

  final CreateClientToken _createClientToken;
  final UpdateClientToken _updateClientToken;
  final ListClientTokenPage _listClientTokenPage;
  final GetClientTokenSecret _getClientTokenSecret;
  final RevokeClientToken _revokeClientToken;
  final DeleteClientToken _deleteClientToken;
  final CountActiveClientTokens _countActiveClientTokens;
  final ITokenAuditStore? _tokenAuditStore;

  List<ClientTokenSummary> _tokens = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isListStale = false;
  bool _disposed = false;
  _TokenMutation? _mutation;
  String? _mutationTokenId;
  String? _copyingTokenSecretId;
  PresentationErrorState? _listErrorState;
  PresentationErrorState? _mutationErrorState;
  PresentationErrorState? _statsErrorState;
  String? _lastCreatedToken;
  ClientTokenUpdateOutcome? _lastUpdateOutcome;
  ClientTokenListQuery _lastListQuery = const ClientTokenListQuery(page: 1, pageSize: 50);
  int _loadGeneration = 0;
  int _dataRevision = 0;
  int _statsGeneration = 0;
  int _currentPage = 1;
  int _pageSize = ClientTokenListQuery.defaultPageSize;
  int _totalCount = 0;
  int _activeTokenCount = 0;

  List<ClientTokenSummary> get tokens => _tokens;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isListStale => _isListStale;
  bool get isCreating => _mutation == _TokenMutation.save;
  bool get isRevoking => _mutation == _TokenMutation.revoke;
  bool get isDeleting => _mutation == _TokenMutation.delete;
  bool get isCopyingTokenSecret => _copyingTokenSecretId != null;
  String? get revokingTokenId => isRevoking ? _mutationTokenId : null;
  String? get deletingTokenId => isDeleting ? _mutationTokenId : null;
  String? get copyingTokenSecretId => _copyingTokenSecretId;
  PresentationErrorState? get errorState => _mutationErrorState ?? _listErrorState ?? _statsErrorState;
  String get error => errorState?.message ?? '';
  String get mutationError => _mutationErrorState?.message ?? '';
  String get listError => (_listErrorState ?? _statsErrorState)?.message ?? '';
  bool get errorCanRetry => errorState?.canRetry ?? false;
  String? get lastCreatedToken => _lastCreatedToken;
  ClientTokenUpdateOutcome? get lastUpdateOutcome => _lastUpdateOutcome;
  bool get isListMutationInProgress => isTokenMutationInProgress;
  bool get isTokenMutationInProgress => _mutation != null;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  int get totalCount => _totalCount;
  int get activeTokenCount => _activeTokenCount;
  bool get hasPreviousPage => _currentPage > 1;
  bool get hasNextPage => _currentPage * _pageSize < _totalCount;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _statsGeneration++;
    super.dispose();
  }

  Future<Result<void>> loadTokens({bool silent = false, ClientTokenListQuery? query}) {
    if (isTokenMutationInProgress || _disposed) {
      return Future.value(Failure(PresentationOperationFailures.operationBlocked));
    }
    return _loadTokens(silent: silent, query: query ?? _lastListQuery);
  }

  Future<Result<void>> _loadTokens({required bool silent, required ClientTokenListQuery query}) async {
    _lastListQuery = query.copyWith(page: query.page ?? 1, pageSize: query.pageSize ?? _pageSize);
    final generation = ++_loadGeneration;
    final revision = _dataRevision;
    if (!silent) {
      _isLoading = true;
      _listErrorState = null;
      notifyListeners();
    }
    final result = await _listClientTokenPage(query: _lastListQuery);
    if (_disposed || generation != _loadGeneration || revision != _dataRevision) {
      return Failure(PresentationOperationFailures.superseded);
    }
    _isLoading = false;
    if (result.isError()) {
      _listErrorState = PresentationErrorState.fromFailure(result.exceptionOrNull()!);
      notifyListeners();
      return Failure(result.exceptionOrNull()!);
    }
    final page = result.getOrThrow();
    _tokens = List.unmodifiable(page.items);
    _currentPage = page.page;
    _pageSize = page.pageSize;
    _totalCount = page.totalCount;
    _lastListQuery = _lastListQuery.copyWith(page: page.page, pageSize: page.pageSize);
    _listErrorState = null;
    _hasLoaded = true;
    _isListStale = false;
    notifyListeners();
    return const Success(unit);
  }

  Future<Result<void>> refreshActiveTokenCount() {
    if (isTokenMutationInProgress || _disposed) {
      return Future.value(Failure(PresentationOperationFailures.operationBlocked));
    }
    return _refreshActiveTokenCount();
  }

  Future<Result<void>> _refreshActiveTokenCount() async {
    final generation = ++_statsGeneration;
    final revision = _dataRevision;
    final result = await _countActiveClientTokens();
    if (_disposed || generation != _statsGeneration || revision != _dataRevision) {
      return Failure(PresentationOperationFailures.superseded);
    }
    if (result.isError()) {
      _statsErrorState = PresentationErrorState.fromFailure(result.exceptionOrNull()!);
      notifyListeners();
      return Failure(result.exceptionOrNull()!);
    }
    _activeTokenCount = result.getOrThrow();
    _statsErrorState = null;
    notifyListeners();
    return const Success(unit);
  }

  Future<Result<void>> _mutate({
    required _TokenMutation mutation,
    required Future<Result<void>> Function() write,
    required bool refreshTokens,
    bool Function()? hasChanges,
    String? tokenId,
  }) async {
    if (isTokenMutationInProgress || _disposed) {
      return Failure(PresentationOperationFailures.operationBlocked);
    }
    _mutation = mutation;
    _mutationTokenId = tokenId;
    _mutationErrorState = null;
    _dataRevision++;
    _loadGeneration++;
    _statsGeneration++;
    _isLoading = false;
    notifyListeners();
    try {
      final result = await write();
      if (result.isError()) {
        _mutationErrorState = PresentationErrorState.fromFailure(result.exceptionOrNull()!);
        return result;
      }
      if (hasChanges != null && !hasChanges()) return const Success(unit);
      _isListStale = true;
      await _refreshActiveTokenCount();
      if (refreshTokens && !_disposed) {
        await _loadTokens(silent: true, query: _lastListQuery);
      }
      return const Success(unit);
    } finally {
      _mutation = null;
      _mutationTokenId = null;
      notifyListeners();
    }
  }

  Future<Result<void>> createToken(ClientTokenCreateRequest request, {bool refreshTokens = true}) {
    return _mutate(
      mutation: _TokenMutation.save,
      refreshTokens: refreshTokens,
      write: () async {
        _lastCreatedToken = null;
        _lastUpdateOutcome = null;
        final result = await _createClientToken(request);
        if (result.isError()) return Failure(result.exceptionOrNull()!);
        _lastCreatedToken = result.getOrThrow();
        return const Success(unit);
      },
    );
  }

  Future<Result<void>> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    bool refreshTokens = true,
    int? expectedVersion,
  }) {
    var changed = true;
    return _mutate(
      mutation: _TokenMutation.save,
      tokenId: tokenId,
      refreshTokens: refreshTokens,
      hasChanges: () => changed,
      write: () async {
        _lastCreatedToken = null;
        _lastUpdateOutcome = null;
        final result = await _updateClientToken(tokenId, request, expectedVersion: expectedVersion);
        if (result.isError()) return Failure(result.exceptionOrNull()!);
        final updated = result.getOrThrow();
        changed = updated.outcome != ClientTokenUpdateOutcome.unchanged;
        _lastUpdateOutcome = updated.outcome;
        _lastCreatedToken = updated.didRotateToken ? updated.tokenValue : null;
        if (updated.outcome != ClientTokenUpdateOutcome.unchanged) {
          _tokens = List.unmodifiable(
            _tokens.map(
              (token) => token.id != tokenId
                  ? token
                  : token.copyWith(
                      clientId: request.normalizedClientId,
                      name: request.normalizedName,
                      agentId: request.normalizedAgentId,
                      payload: request.payload,
                      allTables: request.allTables,
                      allViews: request.allViews,
                      globalPermissions: request.effectiveGlobalPermissions,
                      rules: request.effectiveRules,
                      tokenValue: updated.didRotateToken ? null : token.tokenValue,
                      version: updated.version,
                      updatedAt: updated.updatedAt,
                    ),
            ),
          );
        }
        return const Success(unit);
      },
    );
  }

  Future<Result<void>> revokeToken(String tokenId) => _mutate(
    mutation: _TokenMutation.revoke,
    tokenId: tokenId,
    refreshTokens: true,
    write: () async {
      final result = await _revokeClientToken(tokenId);
      if (result.isError()) return result;
      _tokens = List.unmodifiable(
        _tokens
            .map(
              (token) => token.id != tokenId || token.isRevoked
                  ? token
                  : token.copyWith(
                      isRevoked: true,
                      version: token.version + 1,
                      updatedAt: DateTime.now().toUtc(),
                    ),
            )
            .where((token) => _lastListQuery.status != ClientTokenStatusFilter.active || !token.isRevoked),
      );
      return const Success(unit);
    },
  );

  Future<Result<void>> deleteToken(String tokenId) => _mutate(
    mutation: _TokenMutation.delete,
    tokenId: tokenId,
    refreshTokens: true,
    write: () async {
      final result = await _deleteClientToken(tokenId);
      if (result.isSuccess()) _tokens = List.unmodifiable(_tokens.where((token) => token.id != tokenId));
      return result;
    },
  );

  bool isRevokingToken(String tokenId) => revokingTokenId == tokenId;
  bool isDeletingToken(String tokenId) => deletingTokenId == tokenId;
  bool isCopyingTokenSecretFor(String tokenId) => _copyingTokenSecretId == tokenId;

  Future<Result<ClientTokenSecretLookup>> getTokenSecret(String tokenId) async {
    if (isCopyingTokenSecret || isTokenMutationInProgress || _disposed) {
      return Failure(PresentationOperationFailures.operationBlocked);
    }
    _copyingTokenSecretId = tokenId;
    final revision = _dataRevision;
    notifyListeners();
    try {
      final result = await _getClientTokenSecret(tokenId);
      if (_disposed || revision != _dataRevision) {
        return Failure(PresentationOperationFailures.superseded);
      }
      return result;
    } finally {
      _copyingTokenSecretId = null;
      notifyListeners();
    }
  }

  void clearError() {
    _mutationErrorState = null;
    _listErrorState = null;
    _statsErrorState = null;
    notifyListeners();
  }

  void clearLastCreatedToken() {
    _lastCreatedToken = null;
    notifyListeners();
  }

  void clearLastUpdateOutcome() {
    _lastUpdateOutcome = null;
    notifyListeners();
  }

  Future<void> recordCopiedToken({required String tokenId, required String clientId}) async {
    final store = _tokenAuditStore;
    if (store == null) return;
    try {
      await store.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.copy,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
          clientId: clientId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Token copy audit record failed',
        name: 'client_token_provider',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
