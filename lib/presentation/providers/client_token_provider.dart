import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';

class ClientTokenProvider extends ChangeNotifier {
  ClientTokenProvider(
    this._createClientToken,
    this._listClientTokens,
    this._revokeClientToken,
    this._deleteClientToken,
  );

  final CreateClientToken _createClientToken;
  final ListClientTokens _listClientTokens;
  final RevokeClientToken _revokeClientToken;
  final DeleteClientToken _deleteClientToken;

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

  Future<bool> loadTokens({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = '';
      notifyListeners();
    }

    final result = await _listClientTokens();

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
        await loadTokens(silent: true);
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
        await loadTokens(silent: true);
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
}
