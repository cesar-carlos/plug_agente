import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
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
  );

  final CreateClientToken _createClientToken;
  final ListClientTokens _listClientTokens;
  final RevokeClientToken _revokeClientToken;

  List<ClientTokenSummary> _tokens = const <ClientTokenSummary>[];
  bool _isLoading = false;
  bool _isCreating = false;
  bool _isRevoking = false;
  String _error = '';
  String? _lastCreatedToken;
  bool _hasLoaded = false;

  List<ClientTokenSummary> get tokens => _tokens;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isRevoking => _isRevoking;
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

  Future<bool> createToken(ClientTokenCreateRequest request) async {
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
        await loadTokens(silent: true);
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
    notifyListeners();
    return isSuccess;
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
