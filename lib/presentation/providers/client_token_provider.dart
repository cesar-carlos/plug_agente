import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';

class ClientTokenProvider extends ChangeNotifier {
  ClientTokenProvider(
    this._createClientToken,
    this._updateClientToken,
    this._listClientTokens,
    this._revokeClientToken,
    this._deleteClientToken, {
    ITokenAuditStore? tokenAuditStore,
  }) : _tokenAuditStore = tokenAuditStore;

  final CreateClientToken _createClientToken;
  final UpdateClientToken _updateClientToken;
  final ListClientTokens _listClientTokens;
  final RevokeClientToken _revokeClientToken;
  final DeleteClientToken _deleteClientToken;
  final ITokenAuditStore? _tokenAuditStore;

  List<ClientTokenSummary> _tokens = const <ClientTokenSummary>[];
  bool _isLoading = false;
  bool _isCreating = false;
  bool _isRevoking = false;
  bool _isDeleting = false;
  String? _revokingTokenId;
  String? _deletingTokenId;
  String _error = '';
  String? _lastCreatedToken;
  bool _hasLoaded = false;
  ClientTokenListQuery _lastListQuery = const ClientTokenListQuery();

  List<ClientTokenSummary> get tokens => _tokens;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isRevoking => _isRevoking;
  bool get isDeleting => _isDeleting;
  String? get revokingTokenId => _revokingTokenId;
  String? get deletingTokenId => _deletingTokenId;
  String get error => _error;
  String? get lastCreatedToken => _lastCreatedToken;
  bool get hasLoaded => _hasLoaded;

  Future<bool> loadTokens({
    bool silent = false,
    ClientTokenListQuery? query,
  }) async {
    final effectiveQuery = query ?? _lastListQuery;
    _lastListQuery = effectiveQuery;

    if (!silent) {
      _isLoading = true;
      _error = '';
      notifyListeners();
    }

    final result = await _listClientTokens(query: effectiveQuery);

    var isSuccess = false;
    result.fold(
      (tokens) {
        _tokens = tokens;
        _error = '';
        _hasLoaded = true;
        isSuccess = true;
      },
      (failure) {
        if (!silent) {
          _error = failure.toDisplayMessage();
        }
      },
    );

    if (!silent) {
      _isLoading = false;
      notifyListeners();
    } else if (isSuccess) {
      notifyListeners();
    }

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
        _lastCreatedToken = updateResult.tokenValue;
        isSuccess = true;
        final patched = _applyUpdatedTokenInMemory(
          tokenId: tokenId,
          request: request,
          nextVersion: updateResult.version,
          updatedAt: updateResult.updatedAt,
          rotatedToken: updateResult.tokenValue,
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

  bool isRevokingToken(String tokenId) {
    return _isRevoking && _revokingTokenId == tokenId;
  }

  Future<bool> deleteToken(String tokenId) async {
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
    required String rotatedToken,
  }) {
    final index = _tokens.indexWhere((token) => token.id == tokenId);
    if (index < 0) {
      return false;
    }

    final current = _tokens[index];
    final agentId = request.agentId?.trim();
    final next = current.copyWith(
      clientId: request.clientId.trim(),
      agentId: agentId == null || agentId.isEmpty ? null : agentId,
      payload: request.payload,
      allTables: request.allTables,
      allViews: request.allViews,
      allPermissions: request.allPermissions,
      rules: request.rules,
      tokenValue: rotatedToken,
      version: nextVersion,
      updatedAt: updatedAt,
    );

    final mutable = List<ClientTokenSummary>.from(_tokens);
    mutable[index] = next;
    _tokens = mutable;
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
    _tokens = mutable;
  }
}
