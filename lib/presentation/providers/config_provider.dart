import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class ConfigProvider extends ChangeNotifier {
  ConfigProvider(
    this._saveConfigUseCase,
    this._loadConfigUseCase,
    this._activeConfigResolver,
    this._configService,
    this._uuid,
  ) {
    _loadCurrentConfig();
  }
  final SaveAgentConfig _saveConfigUseCase;
  final LoadAgentConfig _loadConfigUseCase;
  final ActiveConfigResolver _activeConfigResolver;
  final ConfigService _configService;
  final Uuid _uuid;

  Config? _currentConfig;
  bool _isLoading = false;
  String _error = '';
  bool _isPasswordVisible = false;
  int _batchDepth = 0;
  bool _batchedStateChanged = false;
  Future<Result<Config>>? _saveLoopFuture;
  bool _saveRequested = false;
  int _loadRequestToken = 0;

  Config? get currentConfig => _currentConfig;
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get isPasswordVisible => _isPasswordVisible;

  Future<void> _loadCurrentConfig() async {
    _isLoading = true;
    _error = '';
    notifyListeners();

    final result = await _loadConfigUseCase(null);

    result.fold(
      (config) {
        _currentConfig = config;
        AppLogger.info('Config loaded successfully');
      },
      (failure) {
        // NotFoundFailure means no config exists, not an error
        if (failure is domain_errors.NotFoundFailure) {
          _currentConfig = null;
          AppLogger.info('No config found, creating new one');
          _createDefaultConfig();
        } else {
          _error = failure.toDisplayMessage();
          AppLogger.error(
            'Failed to load config: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
        }
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  /// Loads a configuration by ID.
  ///
  /// Use this to load a specific configuration when navigating
  /// with route parameters (e.g., from deep links).
  Future<void> loadConfigById(String id) async {
    final requestToken = ++_loadRequestToken;
    _isLoading = true;
    _error = '';
    notifyListeners();

    final result = await _loadConfigUseCase(id);
    if (requestToken != _loadRequestToken) {
      return;
    }

    if (result.isSuccess()) {
      final config = result.getOrThrow();
      _currentConfig = config;
      await _activeConfigResolver.setActiveConfigId(config.id);
      AppLogger.info('Config loaded successfully by ID: $id');
    } else {
      final failure = result.exceptionOrNull()!;
      _currentConfig = null;
      _error = failure.toDisplayMessage();
      AppLogger.error(
        'Failed to load config: ${failure.toDisplayMessage()}',
        failure.toTechnicalMessage(),
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  void _createDefaultConfig() {
    _currentConfig = Config(
      id: _uuid.v4(),
      agentId: _uuid.v4(),
      driverName: DatabaseDriver.sqlServer.displayName,
      odbcDriverName: 'SQL Server Native Client 11.0',
      connectionString: '',
      username: '',
      password: '',
      databaseName: '',
      host: 'localhost',
      port: 1433,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<Result<Config>> saveConfig() {
    _saveRequested = true;
    final inFlightSave = _saveLoopFuture;
    if (inFlightSave != null) {
      return inFlightSave;
    }

    final saveLoop = _drainSaveRequests().whenComplete(() {
      _saveLoopFuture = null;
    });
    _saveLoopFuture = saveLoop;
    return saveLoop;
  }

  Future<Result<Config>> _drainSaveRequests() async {
    Result<Config>? latestResult;
    while (_saveRequested) {
      _saveRequested = false;
      latestResult = await _performSingleSaveConfig();
    }
    return latestResult ??
        Failure(
          domain_errors.ValidationFailure('Nenhuma configuraÃ§Ã£o para salvar'),
        );
  }

  Future<Result<Config>> _performSingleSaveConfig() async {
    if (_currentConfig == null) {
      _error = 'No configuration to save';
      notifyListeners();
      return Failure(
        domain_errors.ValidationFailure('Nenhuma configuração para salvar'),
      );
    }

    _isLoading = true;
    _error = '';
    notifyListeners();

    // Generate connection string
    final connectionString = _configService.generateConnectionString(
      _currentConfig!,
    );
    final configWithConnectionString = _currentConfig!.copyWith(
      connectionString: connectionString,
      updatedAt: DateTime.now(),
    );

    final result = await _saveConfigUseCase(configWithConnectionString);

    result.fold(
      (savedConfig) {
        _currentConfig = savedConfig;
        _error = '';
        AppLogger.info('Config saved successfully');
        unawaited(_activeConfigResolver.setActiveConfigId(savedConfig.id));
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Failed to save config: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  void batchUpdate(VoidCallback action) {
    _batchDepth++;
    try {
      action();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0 && _batchedStateChanged) {
        _batchedStateChanged = false;
        notifyListeners();
      }
    }
  }

  void _ensureConfigExists() {
    if (_currentConfig == null) {
      _createDefaultConfig();
    }
  }

  void updateServerUrl(String serverUrl) {
    _updateCurrentConfig(
      (config) => config.copyWith(serverUrl: normalizeServerUrl(serverUrl)),
    );
  }

  void updateAgentId(String agentId) {
    _updateCurrentConfig((config) => config.copyWith(agentId: agentId));
  }

  void updateDriverName(String driverName) {
    _updateCurrentConfig((config) => config.copyWith(driverName: driverName));
  }

  void updateOdbcDriverName(String odbcDriverName) {
    _updateCurrentConfig(
      (config) => config.copyWith(odbcDriverName: odbcDriverName),
    );
  }

  void updateUsername(String username) {
    _updateCurrentConfig((config) => config.copyWith(username: username));
  }

  void updatePassword(String password) {
    _updateCurrentConfig((config) => config.copyWith(password: password));
  }

  void updateAuthUsername(String? authUsername) {
    _updateCurrentConfig(
      (config) => config.copyWith(authUsername: authUsername),
    );
  }

  void updateAuthPassword(String? authPassword) {
    _updateCurrentConfig(
      (config) => config.copyWith(authPassword: authPassword),
    );
  }

  void updateDatabaseName(String databaseName) {
    _updateCurrentConfig(
      (config) => config.copyWith(databaseName: databaseName),
    );
  }

  void updateHost(String host) {
    _updateCurrentConfig((config) => config.copyWith(host: host));
  }

  void updatePort(int port) {
    _updateCurrentConfig((config) => config.copyWith(port: port));
  }

  void updateNome(String nome) {
    _updateCurrentConfig((config) => config.copyWith(nome: nome.trim()));
  }

  void updateNomeFantasia(String nomeFantasia) {
    _updateCurrentConfig(
      (config) => config.copyWith(nomeFantasia: nomeFantasia.trim()),
    );
  }

  void updateCnaeCnpjCpf(String cnaeCnpjCpf) {
    _updateCurrentConfig(
      (config) => config.copyWith(cnaeCnpjCpf: cnaeCnpjCpf.trim()),
    );
  }

  void updateTelefone(String telefone) {
    _updateCurrentConfig(
      (config) => config.copyWith(telefone: telefone.trim()),
    );
  }

  void updateCelular(String celular) {
    _updateCurrentConfig(
      (config) => config.copyWith(celular: celular.trim()),
    );
  }

  void updateEmail(String email) {
    _updateCurrentConfig((config) => config.copyWith(email: email.trim()));
  }

  void updateEndereco(String endereco) {
    _updateCurrentConfig(
      (config) => config.copyWith(endereco: endereco.trim()),
    );
  }

  void updateNumeroEndereco(String numeroEndereco) {
    _updateCurrentConfig(
      (config) => config.copyWith(numeroEndereco: numeroEndereco.trim()),
    );
  }

  void updateBairro(String bairro) {
    _updateCurrentConfig((config) => config.copyWith(bairro: bairro.trim()));
  }

  void updateCep(String cep) {
    _updateCurrentConfig((config) => config.copyWith(cep: cep.trim()));
  }

  void updateNomeMunicipio(String nomeMunicipio) {
    _updateCurrentConfig(
      (config) => config.copyWith(nomeMunicipio: nomeMunicipio.trim()),
    );
  }

  void updateUfMunicipio(String ufMunicipio) {
    _updateCurrentConfig(
      (config) => config.copyWith(ufMunicipio: ufMunicipio.trim()),
    );
  }

  void updateObservacao(String observacao) {
    _updateCurrentConfig(
      (config) => config.copyWith(observacao: observacao.trim()),
    );
  }

  void updateAgentProfile(AgentProfile profile) {
    _updateCurrentConfig(profile.applyToConfig);
  }

  /// Persists hub catalog revision after a successful profile PATCH (CAS for next push).
  Future<Result<void>> persistHubProfileCatalogSync({
    required int profileVersion,
    String? profileUpdatedAtIso,
  }) async {
    if (_currentConfig == null) {
      return Failure(
        domain_errors.ValidationFailure('Nenhuma configuração para salvar'),
      );
    }

    _updateCurrentConfig(
      (config) => config.copyWith(
        hubProfileVersion: profileVersion,
        hubProfileUpdatedAt: profileUpdatedAtIso,
        updatedAt: DateTime.now(),
      ),
    );

    final saveResult = await saveConfig();
    return saveResult.fold(
      (_) => const Success(unit),
      Failure.new,
    );
  }

  void togglePasswordVisibility() {
    _isPasswordVisible = !_isPasswordVisible;
    notifyListeners();
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  String getConnectionString() {
    if (_currentConfig == null) return '';
    return _configService.generateConnectionString(_currentConfig!);
  }

  void _updateCurrentConfig(Config Function(Config current) transform) {
    _ensureConfigExists();
    final currentConfig = _currentConfig!;
    final nextConfig = transform(currentConfig);
    if (_configContentsEqual(currentConfig, nextConfig)) {
      return;
    }
    _currentConfig = nextConfig;
    _notifyStateChanged();
  }

  void _notifyStateChanged() {
    if (_batchDepth > 0) {
      _batchedStateChanged = true;
      return;
    }
    notifyListeners();
  }

  bool _configContentsEqual(Config left, Config right) {
    return left.id == right.id &&
        left.serverUrl == right.serverUrl &&
        left.agentId == right.agentId &&
        left.authToken == right.authToken &&
        left.refreshToken == right.refreshToken &&
        left.authUsername == right.authUsername &&
        left.authPassword == right.authPassword &&
        left.driverName == right.driverName &&
        left.odbcDriverName == right.odbcDriverName &&
        left.connectionString == right.connectionString &&
        left.username == right.username &&
        left.password == right.password &&
        left.databaseName == right.databaseName &&
        left.host == right.host &&
        left.port == right.port &&
        left.nome == right.nome &&
        left.nomeFantasia == right.nomeFantasia &&
        left.cnaeCnpjCpf == right.cnaeCnpjCpf &&
        left.telefone == right.telefone &&
        left.celular == right.celular &&
        left.email == right.email &&
        left.endereco == right.endereco &&
        left.numeroEndereco == right.numeroEndereco &&
        left.bairro == right.bairro &&
        left.cep == right.cep &&
        left.nomeMunicipio == right.nomeMunicipio &&
        left.ufMunicipio == right.ufMunicipio &&
        left.observacao == right.observacao &&
        left.hubProfileVersion == right.hubProfileVersion &&
        left.hubProfileUpdatedAt == right.hubProfileUpdatedAt &&
        left.createdAt == right.createdAt &&
        left.updatedAt == right.updatedAt;
  }
}
